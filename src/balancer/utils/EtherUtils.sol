// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {Ownable2Step} from "@openzeppelin/access/Ownable2Step.sol";

/// @title EtherUtils
/// @author centonze.eth
/// @dev Utility contract providing functions to manage WETH allowances.
/// Inherits from Ownable2Step to provide two-step ownership management.
abstract contract EtherUtils is Ownable2Step {
    using SafeTransferLib for ERC20;

    // The WETH token address on Base mainnet.
    address internal constant WETH = 0x4200000000000000000000000000000000000006;

    /// @dev Internal function to maximize the WETH allowance for a target address.
    /// @param target The address for which the WETH allowance will be set to max.
    function _resetWethAllowance(address target) internal {
        ERC20(WETH).safeApprove(target, type(uint256).max);
    }

    /// @dev Internal function to remove the WETH allowance for a target address.
    /// @param target The address for which the WETH allowance will be removed.
    function _removeWethAllowance(address target) internal {
        ERC20(WETH).safeApprove(target, 0);
    }
}