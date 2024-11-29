//** Decubate Staking Contract */
//** Author : Aceson */

//SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.20;

import { AccessControl } from "@openzeppelin/access/AccessControl.sol";
import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { IERC721Enumerable } from "@openzeppelin/interfaces/IERC721Enumerable.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { InterestHelper } from "./libraries/InterestHelper.sol";
import { IDecubateMasterChef } from "./interfaces/IDecubateMasterChef.sol";
import {Initializable} from "@openzeppelin/proxy/utils/Initializable.sol";
import {ABalancer} from "./balancer/zapper/ABalancer.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {RawYieldCalculator} from "./balancer/utils/RawYieldCalculator.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";


contract DecubateMasterChef is AccessControl, InterestHelper, IDecubateMasterChef, Initializable, ABalancer, RawYieldCalculator {
  using SafeERC20 for IERC20;
  /**
   *
   * @dev PoolInfo reflects the info of each pools
   *
   * If APY is 12%, we provide 120 as input. lockPeriodInDays
   * would be the number of days which the claim is locked.
   * So if we want to lock claim for 1 month, lockPeriodInDays would be 30.
   *
   * @param {apy} Percentage of yield produced by the pool
   * @param {lockPeriodInDays} Amount of time claim will be locked
   * @param {totalDeposit} Total deposit in the pool
   * @param {startDate} starting time of pool
   * @param {endDate} ending time of pool in unix timestamp
   * @param {hardCap} Maximum amount a pool can hold
   * @param {token} Token used as deposit/reward
   *
   */


  struct Pool {
    uint256 apy;
    uint256 lockPeriodInDays;
    uint256 totalDeposit;
    uint256 startDate;
    uint256 endDate;
    uint256 hardCap;
    address stakeToken;
    address rewardsToken;

  }

  address private feeAddress; //Address which receives fee
  uint8 private feePercent; //Percentage of fee deducted (/1000)
  uint256 BPTscaling = 120; //Scaling factor for BPT tokens pool weight compensation


  // User data
  mapping(uint256 => mapping(address => User)) public users;
  // Max transfer amount for each token
  mapping(address => uint256) public maxTransferAmount;

  // Pool info
  Pool[] public poolInfo;

  //Manager Role (Admin)
  bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  //Events
  event Stake(address indexed addr, uint256 indexed pid, uint256 indexed amount, uint256 time);
  event Claim(address indexed addr, uint256 indexed pid, uint256 indexed amount, uint256 time);
  event Reinvest(address indexed addr, uint256 indexed pid, uint256 indexed amount, uint256 time);
  event Unstake(address indexed addr, uint256 indexed pid, uint256 indexed amount, uint256 time);
  event FeeValueUpdated(uint8 feeValue, address feeAddress);
  event CompounderUpdated(address compounder);
  event PoolAdded(
    uint256 indexed apy,
    uint256 indexed lockPeriodInDays,
    uint256 endDate,
    uint256 hardCap,
    address indexed stakeToken,
    address  rewardsToken  
  );
  event PoolChanged(
    uint256 indexed  pid,
    uint256 apy,
    uint256 indexed lockPeriodInDays,
    uint256 endDate,
    uint256 indexed hardCap,
    uint256 maxTransfer
  );
  event NFTSet(
    uint256 pid,
    string name,
    address contractAdd,
    bool isUsed,
    uint16 multiplier,
    uint16 startIdx,
    uint16 endIdx
  );
  event TokenTransferred(address token, uint256 amount);
  event ManagerRoleSet(address _user, bool _status);

  //Admin Modifier
  modifier onlyManager() {
    require(hasRole(MANAGER_ROLE, msg.sender), "Only manager");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() Ownable(msg.sender){
  }

  // Initializer
  function initialize(address _admin) external initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER_ROLE, _admin);
    _grantRole(MANAGER_ROLE, msg.sender);

    feeAddress = msg.sender;
    feePercent = 0;
  }

   /**
   * @notice Sets new Manager Role. Only callable by Manager Role
   * @param _user Address of new Manager
   * @param _status true = grant role, false = revoke role
   */
  function setManagerRole(address _user, bool _status) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_status) {
      grantRole(MANAGER_ROLE, _user);
    } else {
      revokeRole(MANAGER_ROLE, _user);
    }

    emit ManagerRoleSet(_user, _status);
  }

  /**
   * @dev update fee values
   *
   * @param _feePercent new fee percentage
   * @param _feeWallet  new fee wallet
   */
  function updateFeeValues(uint8 _feePercent, address _feeWallet) external onlyManager {
    feePercent = _feePercent;
    feeAddress = _feeWallet;

    emit FeeValueUpdated(_feePercent, _feeWallet);
  }

  function updateBPTScaling(uint256 _scaling) external onlyManager {
    BPTscaling = _scaling;
  }

  

  /**
   *
   * @dev Add a new pool
   *
   * @param _apy APY of the pool (/1000)
   * @param _lockPeriodInDays lock period in days
   * @param _endDate  end date of the pool
   * @param _hardCap  hard cap of the pool
   * @param _rewardsToken  token address
   */
  function add(
    uint256 _apy,
    uint256 _lockPeriodInDays,
    uint256 _endDate,
    uint256 _hardCap,
    address _stakeToken,
    address _rewardsToken
  ) external override onlyManager {
    require(_endDate > block.timestamp, "Invalid end date");
    require(_stakeToken != address(0), "Invalid token");
    require(_rewardsToken != address(0), "Invalid token");
    poolInfo.push(
      Pool({
        apy: _apy,
        lockPeriodInDays: _lockPeriodInDays,
        totalDeposit: 0,
        startDate: block.timestamp,
        endDate: _endDate,
        hardCap: _hardCap,
        stakeToken: _stakeToken,
        rewardsToken: _rewardsToken
      })
    );


    maxTransferAmount[_stakeToken] = ~uint256(0);

    emit PoolAdded(_apy, _lockPeriodInDays, _endDate, _hardCap, _stakeToken, _rewardsToken);
  }

  /**
   *
   * @dev Update pool info
   *
   * @param _pid  pool id
   * @param _apy  apy of the pool
   * @param _lockPeriodInDays  lock period in days
   * @param _endDate  end date of the pool
   * @param _hardCap  hard cap of the pool
   * @param _maxTransfer  max transfer amount
   */
  function set(
    uint256 _pid,
    uint256 _apy,
    uint256 _lockPeriodInDays,
    uint256 _endDate,
    uint256 _hardCap,
    uint256 _maxTransfer,
    address _stakeToken,
    address _rewardsToken
  ) external override onlyManager {
    require(_pid < poolLength(), "Invalid Id");

    poolInfo[_pid].apy = _apy;
    poolInfo[_pid].lockPeriodInDays = _lockPeriodInDays;
    poolInfo[_pid].endDate = _endDate;
    poolInfo[_pid].hardCap = _hardCap;
    poolInfo[_pid].stakeToken = _stakeToken;
    poolInfo[_pid].rewardsToken = _rewardsToken;

    maxTransferAmount[poolInfo[_pid].stakeToken] = _maxTransfer;

    emit PoolChanged(_pid, _apy, _lockPeriodInDays, _endDate, _hardCap, _maxTransfer);
  }


  /**
   *
   * @dev deposit tokens to staking for TOKEN allocation
   *
   * @param _pid Id of the pool
   * @param _amount Amount to be staked
   *
   * @return bool Status of stake
   *
   */
  function stake(uint256 _pid, uint256 _amount) external override returns (bool) {
    Pool memory pool = poolInfo[_pid];
    IERC20 token = IERC20(pool.stakeToken);

    //Transfer Stake token to this contract
    token.safeTransferFrom(msg.sender, address(this), _amount);

    _stake(_pid, msg.sender, _amount, false);

    return true;
  }

  /**
   *
   * @dev claim accumulated TOKEN reward for a single pool
   *
   * @param _pid pool identifier
   *
   * @return bool status of claim
   */

  function claim(uint256 _pid) external override returns (bool) {
    //Remove Lock of Rewards since we want to be able to claim while Locked
    //require(canClaim(_pid, msg.sender), "Reward still locked");

    _claim(_pid, msg.sender);

    return true;
  }

  /**
   *
   * @dev claim accumulated TOKEN reward from all pools
   *
   * Beware of gas fee!
   *
   * @return bool status of claim
   *
   */
  function claimAll() external override returns (bool) {
    uint256 len = poolInfo.length;

    for (uint256 pid = 0; pid < len; ++pid) {
      if (canClaim(pid, msg.sender)) {
        _claim(pid, msg.sender);
      }
    }

    return true;
  }

  /**
   *
   * @dev withdraw tokens from Staking
   *
   * @param _pid id of the pool
   * @param _amount amount to be unstaked
   *
   * @return bool Status of stake
   *
   */
  function unStake(uint256 _pid, uint256 _amount) external override returns (bool) {
    User storage user = users[_pid][msg.sender];
    Pool storage pool = poolInfo[_pid];

    require(user.totalInvested >= _amount, "Not enough funds");

    require(canClaim(_pid, msg.sender), "Stake still locked");

    _claim(_pid, msg.sender);

    pool.totalDeposit = pool.totalDeposit - _amount;
    user.totalInvested = user.totalInvested - _amount;

    SafeERC20.safeTransfer(IERC20(pool.stakeToken), msg.sender, _amount);

    emit Unstake(msg.sender, _pid, _amount, block.timestamp);

    return true;
  }

  /**
   *
   * @dev check whether user can claim or not
   *
   * @param _pid  id of the pool
   * @param _addr address of the user
   *
   * @return bool Status of claim
   *
   */

  function canClaim(uint256 _pid, address _addr) public view override returns (bool) {
    User storage user = users[_pid][_addr];
    Pool storage pool = poolInfo[_pid];

    return (block.timestamp >= user.depositTime + (pool.lockPeriodInDays * 1 days));
  }

  /**
   * @dev Reward earned by a user in a pool
   *
   * @param _pid  id of the pool
   * @param _addr  address of the user
   */
   function payout(uint256 _pid, address _addr) public view override returns (uint256 value) {
        User storage user = users[_pid][_addr];
        Pool storage pool = poolInfo[_pid];

        uint256 userIMO = getUserImoBalance(_addr, pool.stakeToken, user.totalInvested) * BPTscaling / 100;

        uint256 from = user.lastPayout > user.depositTime ? user.lastPayout : user.depositTime;
        uint256 to = Math.min(block.timestamp, pool.endDate);


        if (from < to) {
            // Use the new calculateRawYield function
            // Note: pool.apy is assumed to be in basis points (e.g., 1000 for 10% APY)
            value = calculateRawYield(userIMO, pool.apy * 100, from, to);
        }

        return value;
    }

  /**
   *
   * @dev get length of the pools
   *
   * @return uint256 length of the pools
   *
   */
  function poolLength() public view override returns (uint256) {
    return poolInfo.length;
  }

  /**
   *
   * @dev get info of all pools
   *
   * @return PoolInfo[] Pool info struct
   *
   */
  function getPools() external view returns (Pool[] memory) {
    return poolInfo;
  }

  

  /**
   * @dev Internal claim function
   *
   * @param _pid  pool id
   * @param _addr  address of the user
   */
  function _claim(uint256 _pid, address _addr) internal {
    User storage user = users[_pid][_addr];
    Pool memory pool = poolInfo[_pid];

    uint256 amount = payout(_pid, _addr);
    
    if (amount > 0) {
      
      _checkEnoughRewards(_pid, amount);
      
      //user.totalWithdrawn = user.totalWithdrawn + amount;

      uint256 feeAmount = (amount * feePercent) / 1000;

      amount = amount - feeAmount;

      user.lastPayout = block.timestamp;

      user.totalClaimed = user.totalClaimed + amount;

      SafeERC20.safeTransfer(IERC20(pool.rewardsToken), feeAddress, feeAmount);

      SafeERC20.safeTransfer(IERC20(pool.rewardsToken), _addr, amount);
      
    }

    emit Claim(_addr, _pid, amount, block.timestamp);

    
  }

  /**
   * @dev Internal stake function
   *
   * @param _pid  pool id
   * @param _sender  address of the user
   * @param _amount  amount to be staked
   * @param _isReinvest  is reinvest or not
   */
  function _stake(uint256 _pid, address _sender, uint256 _amount, bool _isReinvest) internal {
    User storage user = users[_pid][_sender];
    Pool storage pool = poolInfo[_pid];

    if (!_isReinvest) {
      user.depositTime = block.timestamp;
      require(pool.totalDeposit + _amount <= pool.hardCap, "Pool full");
      uint256 stopDepo = pool.endDate - (pool.lockPeriodInDays * 1 days);
      require(block.timestamp <= stopDepo, "Staking disabled for this pool");
      
    }

    user.totalInvested = user.totalInvested + _amount;
    pool.totalDeposit = pool.totalDeposit + _amount;
    user.lastPayout = block.timestamp;

    emit Stake(_sender, _pid, _amount, block.timestamp);
  }
 
 /**
   * @notice internal function to check if there is enough rewards in the contract
   * @param _pid pool ID
   * @param _amount amount to be claimed
   */
  function _checkEnoughRewards(uint256 _pid, uint256 _amount) internal view {
    address token = poolInfo[_pid].rewardsToken;
    uint256 contractBalance = IERC20(token).balanceOf(address(this));
    uint256 depositedBalance = 0;
    uint256 len = poolLength();

    for (uint256 i = 0; i < len; i++) {
      if (poolInfo[i].rewardsToken == token) {
        depositedBalance += poolInfo[i].totalDeposit;
      }
    }

    require(contractBalance - depositedBalance >= _amount, "Not enough rewards");
  }


 
  /**
   * @notice helper to rescue token if needed, only Callable by Owner
   * @param _pid pool ID
   * @param stakedAmount amount to be rescued
   * @param rewardsAmount amount to be rescued
   */
  function RescueTokens(uint256 stakedAmount, uint256 rewardsAmount, uint256 _pid) external onlyOwner {
    
    address stakedToken = poolInfo[_pid].stakeToken;
    address rewardsToken = poolInfo[_pid].rewardsToken;

    require(stakedToken != address(0), "Invalid token");
    require(rewardsToken != address(0), "Invalid token");


    if(stakedAmount > 0) {
      IERC20 token = IERC20(stakedToken);
      uint256 balance = token.balanceOf(address(this));
      require(balance > 0, "No tokens to rescue");
      token.safeTransfer(owner(), stakedAmount);
    }
    if(rewardsAmount > 0) {
      IERC20 token = IERC20(rewardsToken);
      uint256 balance = token.balanceOf(address(this));
      require(balance > 0, "No tokens to rescue");
      token.safeTransfer(owner(), rewardsAmount);
    }
  }

   // Rescue ETH locked in the contract
    function rescueETH(uint256 amount) external onlyOwner {
        payable(owner()).transfer(amount);
    }

    // Rescue ERC20 tokens locked in the contract
    function rescueToken(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), amount);
    }
}
