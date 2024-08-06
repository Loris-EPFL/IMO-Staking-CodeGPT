// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IbalancerQueries {
    type SwapKind is uint8;

    struct BatchSwapStep {
        bytes32 poolId;
        uint256 assetInIndex;
        uint256 assetOutIndex;
        uint256 amount;
        bytes userData;
    }

    struct ExitPoolRequest {
        address[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

    struct JoinPoolRequest {
        address[2] assets;
        uint256[2] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        address assetIn;
        address assetOut;
        uint256 amount;
        bytes userData;
    }

    function queryBatchSwap(
        SwapKind kind,
        BatchSwapStep[] memory swaps,
        address[] memory assets,
        FundManagement memory funds
    ) external returns (int256[] memory assetDeltas);
    function queryExit(bytes32 poolId, address sender, address recipient, ExitPoolRequest memory request)
        external
        returns (uint256 bptIn, uint256[] memory amountsOut);
    function queryJoin(bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request)
        external
        returns (uint256 bptOut, uint256[] memory amountsIn);
    function querySwap(SingleSwap memory singleSwap, FundManagement memory funds) external returns (uint256);
    function vault() external view returns (address);
}
