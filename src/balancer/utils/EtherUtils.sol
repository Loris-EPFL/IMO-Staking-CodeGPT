// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/// @title EtherUtils
/// @author centonze.eth
/// @dev Utility contract providing functions to manage WETH allowances.
/// Inherits from Ownable2Step to provide two-step ownership management.
abstract contract EtherUtils is Ownable2Step {
    using SafeERC20 for IERC20;

    // The WETH token address on Base mainnet.
    address internal constant WETH = 0x4200000000000000000000000000000000000006;
    // The USDC token address on Base mainnet.
    address public USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
     // Base mainnet address of IMO.
    address public IMO = 	0x5A7a2bf9fFae199f088B25837DcD7E115CF8E1bb;
    // Base mainnet address of IMOETHBPT.
    address public IMOETHBPT = 0x007bb7a4bfc214DF06474E39142288E99540f2b3;

    /// @dev Internal function to maximize the WETH allowance for a target address.
    /// @param target The address for which the WETH allowance will be set to max.
    function _resetWethAllowance(address target) internal {
        IERC20(WETH).safeIncreaseAllowance(target, type(uint256).max);
    }

    /// @dev Internal function to remove the WETH allowance for a target address.
    /// @param target The address for which the WETH allowance will be removed.
    function _removeWethAllowance(address target) internal {
        IERC20(WETH).safeIncreaseAllowance(target, 0);
    }
}