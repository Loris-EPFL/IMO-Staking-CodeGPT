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


contract DecubateMasterChef is AccessControl, InterestHelper, IDecubateMasterChef, Initializable {
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

  address public compounderContract; //Auto compounder
  address private feeAddress; //Address which receives fee
  uint8 private feePercent; //Percentage of fee deducted (/1000)

  // User data
  mapping(uint256 => mapping(address => User)) public users;
  // Max transfer amount for each token
  mapping(address => uint256) public maxTransferAmount;

  // Pool info
  Pool[] public poolInfo;
  // NFT info
  NFTMultiplier[] public nftInfo;

  bytes32 internal constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  event Stake(address indexed addr, uint256 indexed pid, uint256 amount, uint256 time);
  event Claim(address indexed addr, uint256 indexed pid, uint256 amount, uint256 time);
  event Reinvest(address indexed addr, uint256 indexed pid, uint256 amount, uint256 time);
  event Unstake(address indexed addr, uint256 indexed pid, uint256 amount, uint256 time);
  event FeeValueUpdated(uint8 feeValue, address feeAddress);
  event CompounderUpdated(address compounder);
  event PoolAdded(
    uint256 apy,
    uint256 lockPeriodInDays,
    uint256 endDate,
    uint256 hardCap,
    address stakeToken,
    address rewardsToken  
  );
  event PoolChanged(
    uint256 pid,
    uint256 apy,
    uint256 lockPeriodInDays,
    uint256 endDate,
    uint256 hardCap,
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

  modifier onlyManager() {
    require(hasRole(MANAGER_ROLE, msg.sender), "Only manager");
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    //_disableInitializers();
  }

  // Initializer
  function initialize(address _admin) external initializer {
    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    _grantRole(MANAGER_ROLE, _admin);
    _grantRole(MANAGER_ROLE, msg.sender);

    feeAddress = msg.sender;
    feePercent = 5;
  }

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

  /**
   *
   * @dev update compounder contract
   *
   * @param _compounder address of the compounder contract
   *
   */
  function updateCompounder(address _compounder) external override onlyManager {
    require(_compounder != address(0), "Zero address");
    if (compounderContract == address(0)) compounderContract = _compounder;
    for (uint256 i = 0; i < poolInfo.length; i++) {
      IERC20(poolInfo[i].stakeToken).approve(compounderContract, type(uint256).max);
    }

    emit CompounderUpdated(_compounder);
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

    //Init nft struct with dummy data
    nftInfo.push(
      NFTMultiplier({
        active: false,
        name: "",
        contractAdd: address(0),
        startIdx: 0,
        endIdx: 0,
        multiplier: 10
      })
    );

    maxTransferAmount[_stakeToken] = ~uint256(0);
    _stake(poolLength() - 1, compounderContract, 0, false); //Mock deposit for compounder
    IERC20(_stakeToken).approve(compounderContract, type(uint256).max);

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
    address _stakeToken
  ) external override onlyManager {
    require(_pid < poolLength(), "Invalid Id");

    poolInfo[_pid].apy = _apy;
    poolInfo[_pid].lockPeriodInDays = _lockPeriodInDays;
    poolInfo[_pid].endDate = _endDate;
    poolInfo[_pid].hardCap = _hardCap;

    maxTransferAmount[poolInfo[_pid].stakeToken] = _maxTransfer;

    emit PoolChanged(_pid, _apy, _lockPeriodInDays, _endDate, _hardCap, _maxTransfer);
  }

  /**
   *
   * @dev Set NFT boost info
   *
   * @param _pid  pool id
   * @param _name  name of the nft
   * @param _contractAdd  address of the nft contract
   * @param _isUsed  is nft used
   * @param _multiplier  multiplier value
   * @param _startIdx  start index of nft
   * @param _endIdx  end index of nft
   */
  function setNFT(
    uint256 _pid,
    string calldata _name,
    address _contractAdd,
    bool _isUsed,
    uint16 _multiplier,
    uint16 _startIdx,
    uint16 _endIdx
  ) external override onlyManager {
    require(_multiplier >= 10, "Invalid multi");
    require(_startIdx <= _endIdx, "Invalid index");

    NFTMultiplier storage nft = nftInfo[_pid];
    nft.name = _name;
    if (nft.contractAdd == address(0)) {
      nft.contractAdd = _contractAdd;
    }
    nft.active = _isUsed;
    nft.multiplier = _multiplier;
    nft.startIdx = _startIdx;
    nft.endIdx = _endIdx;

    emit NFTSet(_pid, _name, _contractAdd, _isUsed, _multiplier, _startIdx, _endIdx);
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

    token.safeTransferFrom(msg.sender, address(this), _amount);

    //reinvest(_pid); Not needed as stakeTokens are different from RewardsTokens

    _stake(_pid, msg.sender, _amount, false);

    return true;
  }

  /**
   *
   * @dev Handle NFT boost of users from compounder
   *
   * @param _pid id of the pool
   * @param _user user eligible for NFT boost
   * @param _rewardAmount Amount of rewards generated
   *
   * @return uint256 Status of stake
   *
   */
  function handleNFTMultiplier(
    uint256 _pid,
    address _user,
    uint256 _rewardAmount
  ) external override returns (uint256) {
    require(msg.sender == compounderContract, "Only compounder");
    uint16 multi = calcMultiplier(_pid, _user);

    uint256 multipliedAmount = ((_rewardAmount * multi) / 10) - _rewardAmount;

    if (multipliedAmount > 0) {
      _checkEnoughRewards(_pid, multipliedAmount);
      SafeERC20.safeTransfer(IERC20(poolInfo[_pid].rewardsToken), _user, multipliedAmount);
    }

    return multipliedAmount;
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
    require(canClaim(_pid, msg.sender), "Reward still locked");


    _claim(_pid, msg.sender);

    return true;
  }

  /**
   *
   * @dev Reinvest accumulated TOKEN reward for a single pool
   *
   * @param _pid pool identifier
   *
   * @return bool status of reinvest
   */

  function reinvest(uint256 _pid) public override returns (bool) {
    uint256 amount = payout(_pid, msg.sender);
    if (amount > 0) {
      _checkEnoughRewards(_pid, amount);
      _stake(_pid, msg.sender, amount, true);
      emit Reinvest(msg.sender, _pid, amount, block.timestamp);
    }

    return true;
  }

  /**
   *
   * @dev Reinvest accumulated TOKEN reward for all pools
   *
   * @return bool status of reinvest
   */

  function reinvestAll() external override returns (bool) {
    uint256 len = poolInfo.length;
    for (uint256 pid = 0; pid < len; ++pid) {
      reinvest(pid);
    }

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

    if (msg.sender == compounderContract) {
      return true;
    }

    return (block.timestamp >= user.depositTime + (pool.lockPeriodInDays * 1 days));
  }

  /**
   *
   * @dev check whether user have NFT multiplier
   *
   * @param _pid  id of the pool
   * @param _addr address of the user
   *
   * @return multi Value of multiplier
   *
   */

  function calcMultiplier(uint256 _pid, address _addr) public view override returns (uint16 multi) {
    NFTMultiplier memory nft = nftInfo[_pid];

    if (nft.active && ownsCorrectNFT(_addr, _pid) && _addr != compounderContract) {
      multi = nft.multiplier;
    } else {
      multi = 10;
    }
  }

  /**
   * @dev Check if user owns correct NFT
   *
   * @param _addr  address of the user
   * @param _pid  id of the pool
   */
  function ownsCorrectNFT(address _addr, uint256 _pid) public view returns (bool) {
    NFTMultiplier memory nft = nftInfo[_pid];

    uint256[] memory ids = walletOfOwner(nft.contractAdd, _addr);
    for (uint256 i = 0; i < ids.length; i++) {
      if (ids[i] >= nft.startIdx && ids[i] <= nft.endIdx) {
        return true;
      }
    }
    return false;
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

    uint256 from = user.lastPayout > user.depositTime ? user.lastPayout : user.depositTime;
    uint256 to = block.timestamp > pool.endDate ? pool.endDate : block.timestamp;

    uint256 multiplier = calcMultiplier(_pid, _addr);

    if (from < to) {
      uint256 rayValue = yearlyRateToRay((pool.apy * 10 ** 18) / 1000);
      value = accrueInterest(user.totalInvested, rayValue, to - from) - user.totalInvested;
    }

    value = (value * multiplier) / 10;

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
   * @dev Token transfer function
   *
   * @param _token  token address
   * @param _to  address of the receiver
   * @param _amount  amount to be transferred
   */
  function safeTOKENTransfer(address _token, address _to, uint256 _amount) internal {
    IERC20 token = IERC20(_token);
    uint256 maxTx = maxTransferAmount[_token];
    uint256 amount = _amount;

    while (amount > maxTx) {
      token.safeTransfer(_to, maxTx);
      amount = amount - maxTx;
    }

    if (amount > 0) {
      token.safeTransfer(_to, amount);
    }
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

    emit Claim(_addr, _pid, amount, block.timestamp);

    


    if (amount > 0) {
      
      _checkEnoughRewards(_pid, amount);
      

      user.totalWithdrawn = user.totalWithdrawn + amount;

    
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

    if (!_isReinvest || _sender != compounderContract) {
      user.depositTime = block.timestamp;
      if (_sender != compounderContract) {
        require(pool.totalDeposit + _amount <= pool.hardCap, "Pool full");
        uint256 stopDepo = pool.endDate - (pool.lockPeriodInDays * 1 days);
        require(block.timestamp <= stopDepo, "Staking disabled for this pool");
      }
    }

    user.totalInvested = user.totalInvested + _amount;
    pool.totalDeposit = pool.totalDeposit + _amount;
    user.lastPayout = block.timestamp;

    emit Stake(_sender, _pid, _amount, block.timestamp);
  }

  /**
   * @dev Get NFTs of owner
   *
   * @param _contract  address of the nft contract
   * @param _owner  address of the owner
   */
  function walletOfOwner(
    address _contract,
    address _owner
  ) internal view returns (uint256[] memory) {
    IERC721Enumerable nft = IERC721Enumerable(_contract);
    uint256 tokenCount = nft.balanceOf(_owner);

    uint256[] memory tokensId = new uint256[](tokenCount);
    for (uint256 i; i < tokenCount; i++) {
      tokensId[i] = nft.tokenOfOwnerByIndex(_owner, i);
    }
    return tokensId;
  }

  function _checkEnoughRewards(uint256 _pid, uint256 _amount) internal view {
    address token = poolInfo[_pid].rewardsToken;
    uint256 contractBalance = IERC20(token).balanceOf(address(this));
    uint256 depositedBalance;
    uint256 len = poolLength();

    for (uint256 i = 0; i < len; i++) {
      if (poolInfo[i].rewardsToken == token) {
        depositedBalance += poolInfo[i].totalDeposit;
      }
    }

    require(contractBalance - depositedBalance >= _amount, "Not enough rewards");
  }
}
