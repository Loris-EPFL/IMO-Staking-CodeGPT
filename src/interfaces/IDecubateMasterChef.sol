// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

interface IDecubateMasterChef {
 
   
  /**
   *
   * @dev User reflects the info of each user
   *
   *
   * @param {totalInvested} how many tokens the user staked
   * @param {totalWithdrawn} how many tokens withdrawn so far
   * @param {lastPayout} time at which last claim was done
   * @param {depositTime} Time of last deposit
   * @param {totalClaimed} Total claimed by the user
   *
   */
  struct User {
    uint256 totalInvested;
    uint256 totalWithdrawn;
    uint256 lastPayout;
    uint256 depositTime;
    uint256 totalClaimed;
  }

  function add(
    uint256 _apy,
    uint256 _lockPeriodInDays,
    uint256 _endDate,
    uint256 _hardCap,
    address stakeToken,
    address rewardsToken

  ) external;

  function set(
    uint256 _pid,
    uint256 _apy,
    uint256 _lockPeriodInDays,
    uint256 _endDate,
    uint256 _hardCap,
    uint256 _maxTransfer,
    address _stakeToken,
    
    address _rewardsToken

  ) external;

  function stake(uint256 _pid, uint256 _amount) external returns (bool);

  function claim(uint256 _pid) external returns (bool);

  function claimAll() external returns (bool);

  function unStake(uint256 _pid, uint256 _amount) external returns (bool);

  function canClaim(uint256 _pid, address _addr) external view returns (bool);


  function payout(uint256 _pid, address _addr) external view returns (uint256 value);

  function poolInfo(
    uint256
  )
    external
    view
    returns (
      uint256 apy,
      uint256 lockPeriodInDays,
      uint256 totalDeposit,
      uint256 startDate,
      uint256 endDate,
      uint256 hardCap,
      address stakeToken,
      address rewardsToken

    );

  function users(
    uint256,
    address
  )
    external
    view
    returns (
      uint256 totalInvested,
      uint256 totalWithdrawn,
      uint256 lastPayout,
      uint256 depositTime,
      uint256 totalClaimed
    );

  function poolLength() external view returns (uint256);
}
