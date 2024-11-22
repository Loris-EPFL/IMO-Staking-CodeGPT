// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";

interface IDCBVault {
    function deposit(uint256 _pid, uint256 _amount, address receiver) external payable;
    function withdrawAll(uint256 _pid) external;
    function harvestAll() external;
    function setCallFee(uint256 _callFee) external;
    function setDepositFee(address _feeReceiver, uint256 _depositFee) external;
    function setRebateInfo(uint256 _pid, Rebate memory _rebate) external;
    function pause() external;
    function unpause() external;
    function calculateTotalPendingRewards(uint256 _pid) external view returns (uint256 amount);
    function calculateHarvestDcbRewards(uint256 _pid) external view returns (uint256 currentCallFee);
    function getRewardOfUser(address _user, uint256 _pid) external view returns (uint256 reward);
    function canUnstake(address _user, uint256 _pid) external view returns (bool);
    function balanceOf(uint256 _pid) external view returns (uint256);
    function getPricePerFullShare(uint256 _pid) external view returns (uint256);

    struct Rebate {
        bool isEarlyWithdrawActive;
        uint256 rebatePercent;
        uint256 earlyWithdrawPenalty;
    }
}
