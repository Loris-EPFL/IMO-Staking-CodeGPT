// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

import {Errors} from "./Errors.sol";
import {ISwapRouter} from "./uniswap/ISwapRouter.sol";
import {IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {EtherUtils} from "../utils/EtherUtils.sol";
import {console2} from "forge-std/console2.sol";
import {IQuoterV2} from "./uniswap/IQuoterV2.sol";

/// @title AUniswap
/// @author centonze.eth
/// @notice Utility functions related to Uniswap operations.
abstract contract AUniswap is EtherUtils{
    using SafeERC20 for IERC20;

    // The uniswap pool fee for each token.
    mapping(address => uint24) public uniswapFees;
    // Address of Uniswap V3 router
    ISwapRouter public swapRouter = ISwapRouter(0x2626664c2603336E57B271c5C0b26F421741e481);
    IQuoterV2 public quoteRouter = IQuoterV2(0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a);

    uint24 fee1 = 100; //fee tier of 0.01%
    uint24 fee2 = 500; //fee tier of 0.05%

    /// @notice Emitted when the Uniswap router address is updated.
    /// @param newRouter The address of the new router.
    event SetUniswapRouter(address newRouter);

    /// @notice Emitted when the Uniswap fee for a token is updated.
    /// @param token The token whose fee has been updated.
    /// @param fee The new fee value.
    event SetUniswapFee(address indexed token, uint24 fee);

    /// @notice Sets a new address for the Uniswap router.
    /// @param _swapRouter The address of the new router.
    function setUniswapRouter(address _swapRouter) external onlyOwner {
        if (_swapRouter == address(0)) revert Errors.ZeroAddress();
        swapRouter = ISwapRouter(_swapRouter);

        emit SetUniswapRouter(_swapRouter);
    }

    /// @dev Internal function to set Uniswap fee for a token.
    /// @param token The token for which to set the fee.
    /// @param fee The fee to be set.
    function _setUniswapFee(address token, uint24 fee) internal {
        uniswapFees[token] = fee;

        emit SetUniswapFee(token, fee);
    }

    /// @dev Resets allowance for the Uniswap router for a specific token.
    /// @param token The token for which to reset the allowance.
    function _resetUniswapAllowance(address token) internal {
        IERC20(token).safeIncreaseAllowance(address(swapRouter), type(uint256).max);
    }

    /// @dev Removes allowance for the Uniswap router for a specific token.
    /// @param token The token for which to remove the allowance.
    function _removeUniswapAllowance(address token) internal {
        IERC20(token).safeIncreaseAllowance(address(swapRouter), 0);
    }

    /// @dev Converts a given amount of GHO into DAI using Uniswap.
    /// @param amountIn The amount of token to be swapped.
    /// @param minAmountOut The minimum amount of DAI expected in return.
    /// @return amountOut The amount of DAI received from the swap.
    function _swapToWETH(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: WETH,
            fee: fee2,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);
    }

    function _quoteSwapToWETH(uint256 quoteAmountIn) internal returns (uint256 amountOut, uint256 gasEstimate) {
        IQuoterV2.QuoteExactInputSingleParams memory params = IQuoterV2.QuoteExactInputSingleParams({
            tokenIn: USDC,
            tokenOut: WETH,
            fee: fee2,
            amountIn: quoteAmountIn,
            sqrtPriceLimitX96: 0
        });

        (amountOut, , , gasEstimate) = quoteRouter.quoteExactInputSingle(params);
    }

    
}