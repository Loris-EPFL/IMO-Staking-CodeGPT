// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { AccessControl } from "@openzeppelin/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { Pausable } from "@openzeppelin/utils/Pausable.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import { IDecubateMasterChef } from "./interfaces/IDecubateMasterChef.sol";
import {ABalancer} from "./balancer/zapper/ABalancer.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IWETH} from "./balancer/interfaces/IWETH.sol";

/**
 * @title DCBVault
 * @dev Vault contract for managing user deposits, staking, and rewards distribution
 */
contract DCBVault is AccessControl, Pausable, Initializable, ABalancer {
  using SafeERC20 for IERC20;

  struct UserInfo {
    uint256 shares; // number of shares for a user
    uint256 lastDepositedTime; // keeps track of deposited time for potential penalty
    uint256 totalInvested; // Total amount of token invested
    uint256 totalClaimed; // Total amount of token claimed
    uint256 rewardsDebt; // The amount of rewards already accounted for

  }

  struct PoolInfo {
    uint256 totalShares; // Total shares in the pool
    uint256 pendingClaim; // Claim stored when pool is full
    uint256 lastHarvestedTime; // keeps track of the last pool update
  }

  struct Rebate {
    bool isEarlyWithdrawActive; // If early withdraw is active
    uint256 rebatePercent; // Rebate percent
    uint256 earlyWithdrawPenalty; // Penalty for early withdraw
  }

  struct Fee {
    uint256 depositFee;
    address feeReceiver;
  }

  IDecubateMasterChef public masterchef; // MasterChef contract

  uint256 public callFee; // Fee to call harvestAll function
  uint256 internal constant DIVISOR = 10000;
  uint8 balancerPoolWeight = 75;

  // User staking info
  mapping(uint256 => mapping(address => UserInfo)) public users;
  // Pool info
  mapping(uint256 => PoolInfo) public pools;

  mapping(uint256 => uint256) public accumulatedRewardsPerShare;

  // Pool rebate info
  mapping(uint256 => Rebate) public rebates;
  // Deposit fee info
  Fee public fee;

  bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  event Deposit(
    address indexed sender,
    uint256 indexed poolId,
    uint256 amount,
    uint256 lastDepositedTime
  );
  event Withdraw(address indexed sender, uint256 indexed poolId, uint256 amount, uint256 time);
  event Harvest(address indexed sender, uint256 indexed poolId, uint256 time);
  event WithdrawPenalty(address indexed sender, uint256 indexed poolId, uint256 amount);
  event RebateSent(address indexed sender, uint256 indexed poolId, uint256 amount);
  event Pause();
  event Unpause();
  event CallFeeSet(uint256 callFee);
  event RebateInfoSet(uint256 pid, Rebate rebate);
  event TokenTransferred(address token, uint256 amount);
  event DepositFee(address feeReceiver, uint256 depositFee);
  event ManagerRoleSet(address _user, bool _status);

  error NoBalance();
  error NullAmount();
  error IncorrectAmount();
  error AddressZero();
  error NotApproved();

  modifier onlyManager() {
    require(hasRole(MANAGER_ROLE, msg.sender), "Only manager");
    _;
  }

  /**
   * @notice Modifier to prevent contract interactions
   */
  modifier notContract() {
    require(msg.sender == tx.origin && msg.sender.code.length == 0, "contract not allowed");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address initialOwner) Ownable(initialOwner) {
  }

  function updateBalancerPoolWeight(uint8 _balancerPoolWeight) external onlyManager {
    require(_balancerPoolWeight > 0 && _balancerPoolWeight <= 100, "Invalid weight");
    balancerPoolWeight = _balancerPoolWeight;
  }

  /**
   * @notice Initializes the contract with the MasterChef contract address
   * @param _masterchef Address of the MasterChef contract
   */
  function initialize(IDecubateMasterChef _masterchef, address _admin) external initializer {
    require(address(_masterchef) != address(0), "Zero address");
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER_ROLE, _admin);

    masterchef = IDecubateMasterChef(_masterchef);
    callFee = 0;

    // Set default deposit fee
    fee.depositFee = 0;
    fee.feeReceiver = msg.sender;
  }

  function setManagerRole(address _user, bool _status) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_status) {
      grantRole(MANAGER_ROLE, _user);
    } else {
      revokeRole(MANAGER_ROLE, _user);
    }

    emit ManagerRoleSet(_user, _status);
  }

  function zapEtherAndStakeIMO(uint256 _pid)
        external
        payable
        nonReentrant()
        returns (uint256 stakedAmount)
    {
      if (msg.sender == address(0)) revert AddressZero();
      if (msg.value == 0) revert NullAmount();
      if(paused()) revert EnforcedPause();
      
        PoolInfo storage pool = pools[_pid];

        (
          ,
          uint256 lockPeriodInDays,
          uint256 totalDeposit,
          ,
          uint256 endDate,
          uint256 hardCap,
          address stakeToken,
          
        ) = masterchef.poolInfo(_pid);

        uint256 stopDepo = endDate - (lockPeriodInDays * 1 days);
        require(block.timestamp <= stopDepo, "Staking disabled for this pool");

        IERC20 stakeTokenERC = IERC20(stakeToken);

        uint256 bptBalanceBefore = stakeTokenERC.balanceOf(address(this));

        uint256 EthToZap = (msg.value * balancerPoolWeight) /100;

        IWETH(0x4200000000000000000000000000000000000006).deposit{value: msg.value}();
        bool isVaultApproved = IWETH(0x4200000000000000000000000000000000000006).approve(vault, msg.value);
        if(!isVaultApproved) revert NotApproved();
        uint256 EthAmount = msg.value - EthToZap;

        if(EthToZap == 0 || EthAmount == 0) revert IncorrectAmount();

        //Zap eth to IMO
        uint256 ImoAmount = ethToImo(EthToZap, 0, address(this), address(this)); 
        if(ImoAmount == 0) revert IncorrectAmount();

        //Join imo pool (IMO is given from Vault internal Balance, WETH is given from here)
        joinImoPool(EthAmount, ImoAmount, address(this), address(this));

        // Stake the received BPT tokens
        stakedAmount = stakeTokenERC.balanceOf(address(this)) - bptBalanceBefore; //get new BPT balance of contract
        if(stakedAmount == 0 || totalDeposit + stakedAmount >= hardCap) revert IncorrectAmount();

        uint256 poolBal = balanceOf(_pid);
        poolBal += masterchef.payout(_pid, address(this));

        uint256 currentShares = 0;

        if (pool.totalShares != 0) {
          currentShares = (stakedAmount * pool.totalShares) / poolBal;
        } else {
          stakeTokenERC.safeIncreaseAllowance(address(masterchef), type(uint256).max);
          currentShares = stakedAmount;
        }

        UserInfo storage user = users[_pid][msg.sender];

        user.shares += currentShares;
        user.lastDepositedTime = block.timestamp;
        user.totalInvested += stakedAmount;

        pool.totalShares += currentShares;
        pool.pendingClaim += stakedAmount;

        _earn(_pid);

        emit Deposit(msg.sender, _pid, stakedAmount, block.timestamp);
        return(stakedAmount);
            
    }


  /**
   * @notice Deposits tokens into the DCB Vault
   * @param _pid Pool id
   * @param _amount Amount of tokens to deposit
   */
  function deposit(uint256 _pid, uint256 _amount) external whenNotPaused notContract {
    require(_amount > 0, "Nothing to deposit");

    PoolInfo storage pool = pools[_pid];
    IERC20 token;
    {
      (
        ,
        uint256 lockPeriodInDays,
        uint256 totalDeposit,
        ,
        uint256 endDate,
        uint256 hardCap,
        address stakeToken,
      ) = masterchef.poolInfo(_pid);

      require(totalDeposit + _amount <= hardCap, "Pool full");
      uint256 stopDepo = endDate - (lockPeriodInDays * 1 days);
      require(block.timestamp <= stopDepo, "Staking disabled for this pool");

      token = IERC20(stakeToken);
    }

    uint256 poolBal = balanceOf(_pid);
    token.safeTransferFrom(msg.sender, address(this), _amount);

    uint256 currentShares = 0;

    if (pool.totalShares != 0) {
      currentShares = (_amount * pool.totalShares) / poolBal;
    } else {
      token.safeIncreaseAllowance(address(masterchef), type(uint256).max);
      currentShares = _amount;
    }

    UserInfo storage user = users[_pid][msg.sender];

    user.shares += currentShares;
    user.lastDepositedTime = block.timestamp;
    user.totalInvested += _amount;
    user.rewardsDebt = (user.shares * accumulatedRewardsPerShare[_pid]) / 1e12;


    pool.totalShares += currentShares;
    pool.pendingClaim += _amount;

    _earn(_pid);

    emit Deposit(msg.sender, _pid, _amount, block.timestamp);
  }

  /**
   * @notice Withdraws all funds from the DCB Vault of a user
   * @param _pid Pool id
   */
  function withdrawAll(uint256 _pid) external notContract {
    withdraw(_pid, users[_pid][msg.sender].shares);
  }

  /**
   * @notice Harvests all pools
   * @dev Only possible when contract not paused.
   */
  function harvestAll() external notContract whenNotPaused {
    uint256 poolLen = masterchef.poolLength();

    for (uint256 pid = 0; pid < poolLen; pid++) {
      harvest(pid);
    }
  }

  /**
   * @notice Sets the call fee
   * @param _callFee New call fee
   */
  function setCallFee(uint256 _callFee) external onlyManager {
    require(_callFee < DIVISOR / 2, "Invalid");
    callFee = _callFee;

    emit CallFeeSet(_callFee);
  }

  /**
   * @notice Sets the deposit fee
   * @param _feeReceiver Address of the fee receiver
   * @param _depositFee New deposit fee
   */
  function setDepositFee(address _feeReceiver, uint256 _depositFee) external {
    require(msg.sender == fee.feeReceiver, "Not allowed");
    require(_depositFee < DIVISOR / 2, "Invalid");
    fee.depositFee = _depositFee;
    fee.feeReceiver = _feeReceiver;
  }

  /**
   * @notice Sets rebate info
   * @param _pid Pool id
   * @param _rebate New rebate info
   */
  function setRebateInfo(uint256 _pid, Rebate memory _rebate) external onlyManager {
    require(
      _rebate.rebatePercent <= DIVISOR && _rebate.earlyWithdrawPenalty <= DIVISOR,
      "Invalid rebate percent"
    );
    rebates[_pid] = _rebate;

    emit RebateInfoSet(_pid, _rebate);
  }

  /**
   * @notice Triggers stopped state
   * @dev Only possible when contract not paused.
   */
  function pause() external onlyManager whenNotPaused {
    _pause();
    emit Pause();
  }

  /**
   * @notice Returns to normal state
   * @dev Only possible when contract is paused.
   */
  function unpause() external onlyManager whenPaused {
    _unpause();
    emit Unpause();
  }

  /**
   * @notice Calculates the total pending reward of a pool
   * @param _pid Pool id
   * @return amount Total pending reward
   */
  function calculateTotalPendingRewards(uint256 _pid) external view returns (uint256 amount) {
    amount = masterchef.payout(_pid, address(this));
    amount += pools[_pid].pendingClaim;

    return amount;
  }

  /**
   * @notice Calculate the reward user receives on harvest
   * @param _pid Pool id
   * @return currentCallFee Reward amount
   */
  function calculateHarvestDcbRewards(uint256 _pid) external view returns (uint256 currentCallFee) {
    uint256 amount = masterchef.payout(_pid, address(this));
    amount += pools[_pid].pendingClaim;
    currentCallFee = (amount * callFee) / DIVISOR;

    return currentCallFee;
  }

  /**
 * @notice Calculate the reward user receives on withdraw
 * @param _user User address
 * @param _pid Pool id
 * @return reward Reward amount
 */
function getRewardOfUser(address _user, uint256 _pid) external view returns (uint256 reward) {
    UserInfo storage user = users[_pid][_user];
    PoolInfo storage pool = pools[_pid];

    uint256 accRewardsPerShare = accumulatedRewardsPerShare[_pid];
    uint256 lpSupply = pool.totalShares;

    uint256 pending = (user.shares * accRewardsPerShare) / 1e12 - user.rewardsDebt;
    return pending;
}


  /**
   * @notice Withdraws funds from the DCB Vault
   * @param _pid Pool id
   * @param _shares Number of shares to withdraw
   */
  function withdraw(uint256 _pid, uint256 _shares) public notContract {

    PoolInfo storage pool = pools[_pid];
    UserInfo storage user = users[_pid][msg.sender];

    require(_shares > 0, "Nothing to withdraw");
    require(_shares <= user.shares, "Withdraw exceeds balance");
    require(canUnstake(msg.sender, _pid), "Stake still locked");

    harvest(_pid);

    uint256 currentAmount = (balanceOf(_pid) * _shares) / pool.totalShares;
  
    uint256 totalReward = currentAmount - (user.totalInvested * _shares) / user.shares;

    user.rewardsDebt = (user.shares * accumulatedRewardsPerShare[_pid]) / 1e12;
    user.totalInvested -= (user.totalInvested * _shares) / user.shares;
    user.shares -= _shares;
    pool.totalShares -= _shares;
   
    IERC20 token = getTokenOfPool(_pid);
    bool didUnstake = masterchef.unStake(_pid, currentAmount);
    require(didUnstake, "Unstake failed");

    token.safeTransfer(msg.sender, currentAmount);

    emit Withdraw(msg.sender, _pid, currentAmount, block.timestamp);
  }

  /**
   * @notice Harvests the pool rewards
   * @param _pid Pool id
   */
  function harvest(uint256 _pid) public notContract whenNotPaused {
    PoolInfo storage pool = pools[_pid];
    UserInfo storage user = users[_pid][msg.sender];

    IERC20 token = getRewardTokenOfPool(_pid);

    uint256 prevBal = token.balanceOf(address(this));
    
    bool isClaimSuccess = masterchef.claim(_pid);
    require(isClaimSuccess, "Claim failed");
    
    uint256 claimed = token.balanceOf(address(this)) - prevBal;
    
    uint256 currentCallFee = (claimed * callFee) / DIVISOR;
    claimed -= currentCallFee;
    // Update accumulated rewards per share
    accumulatedRewardsPerShare[_pid] += (claimed * 1e12) / pool.totalShares;
    
    // Calculate the user's share of rewards
    uint256 pending = (user.shares * accumulatedRewardsPerShare[_pid]) / 1e12 - user.rewardsDebt;
    
    if (pending > 0) {
        SafeERC20.safeTransfer(token, msg.sender, pending);
        user.totalClaimed += pending;
    }
    
    // Update user's rewards debt
    user.rewardsDebt = (user.shares * accumulatedRewardsPerShare[_pid]) / 1e12;

    pool.lastHarvestedTime = block.timestamp;

    emit Harvest(msg.sender, _pid, block.timestamp);
}


  /**
   * @notice Returns the price per full share
   * @param _pid Pool id
   * @return Price per full share
   */
  function getPricePerFullShare(uint256 _pid) public view returns (uint256) {
    PoolInfo memory pool = pools[_pid];

    return pool.totalShares == 0 ? 1e18 : (balanceOf(_pid) * 1e18) / pool.totalShares;
  }

  /**
   * @notice Checks if the user can unstake
   * @param _user User address
   * @param _pid Pool id
   * @return Whether unstaking is allowed
   */
  function canUnstake(address _user, uint256 _pid) public view returns (bool) {
    UserInfo storage user = users[_pid][_user];
    (, uint256 lockPeriod, , , , , ,) = masterchef.poolInfo(_pid);

    return (block.timestamp >= user.lastDepositedTime + (lockPeriod * 1 days) ||
      rebates[_pid].isEarlyWithdrawActive);
  }

  /**
   * @notice Returns the balance staked on the pool
   * @param _pid Pool id
   * @return Balance staked
   */
  function balanceOf(uint256 _pid) public view returns (uint256) {
    (uint256 amount, , , , ) = masterchef.users(_pid, address(this));

    return amount;
  }

  /**
   * @notice Stake token to the pool
   * @param _pid Pool id
   */
  function _earn(uint256 _pid) internal {
    uint256 bal = pools[_pid].pendingClaim;
    if (bal > 0) {
      masterchef.stake(_pid, bal);
      pools[_pid].pendingClaim = 0;
    }
  }

  /**
   * @notice Returns the stake token of the pool
   * @param _pid Pool id
   * @return Token of the pool
   */
  function getTokenOfPool(uint256 _pid) internal view returns (IERC20) {
    (, , , , , , address token,) = masterchef.poolInfo(_pid);
    return IERC20(token);
  }

  function getRewardTokenOfPool(uint256 _pid) internal view returns (IERC20) {
    (, , , , , , , address rewardToken) = masterchef.poolInfo(_pid);
    return IERC20(rewardToken);
  }
}
