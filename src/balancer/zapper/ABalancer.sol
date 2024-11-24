// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {Errors} from "./Errors.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "../utils/SafeTransferLib.sol";
import {IVault} from "../interfaces/IVault.sol";
import {EtherUtils} from "../utils/EtherUtils.sol";
import {IVault} from "../interfaces/IVault.sol";
import {IbalancerQueries} from "../interfaces/IbalancerQueries.sol";
import  "@openzeppelin/utils/ReentrancyGuard.sol";   
import "../utils/WeightedPoolUserData.sol";



abstract contract ABalancer is EtherUtils, ReentrancyGuard {
    using SafeTransferLib for ERC20;

    // Base mainnet address of IMO.
    address public IMO = 	0x5A7a2bf9fFae199f088B25837DcD7E115CF8E1bb;

    address public USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;

    address public IMOETHBPT = 0x007bb7a4bfc214DF06474E39142288E99540f2b3;


    // Base mainnet address balanlcer vault.
    address internal vault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    // Base mainnet id for balancer IMO-WETH pool.
    bytes32 internal IMOpoolId = 0x007bb7a4bfc214df06474e39142288e99540f2b3000200000000000000000191;

    bytes32 internal USDCpoolId = 0x4c42b5057a8663e2b1ac21685d1502c937a0381700020000000000000000019c;
    //Base mainnet Address of Balancer Queries 
    address internal balancerQueries = 0x300Ab2038EAc391f26D9F895dc61F8F66a548833;


    /// @notice Emitted when the Balancer vault address is updated.
    /// @param newVault The address of the new Balancer vault.
    event SetBalancerVault(address newVault);

    /// @notice Emitted when the Balancer pool ID is updated.
    /// @param newPoolId The new pool ID.
    event SetBalancerPoolId(bytes32 newPoolId);

    event SetImoAddress(address newAddress);


     /// @notice Sets a new address for the IMO address.
    /// @param _newAddress The address of the new IMO Token.
    function setImoAddress(address _newAddress) external onlyOwner {
        IMO = _newAddress;

        emit SetImoAddress(_newAddress);
    }

    /// @notice Sets a new address for the Balancer vault.
    /// @param _vault The address of the new Balancer vault.
    function setBalancerVault(address _vault) external onlyOwner {
        if (_vault == address(0)) revert Errors.ZeroAddress();
        vault = _vault;

        emit SetBalancerVault(_vault);
    }

    /// @notice Sets a new pool ID for Balancer operations.
    /// @param _poolId The new pool ID.
    function setBalancerPoolId(bytes32 _poolId) external onlyOwner {
        IMOpoolId = _poolId;

        emit SetBalancerPoolId(_poolId);
    }

    function setBalancerQueries(address _balancerQueries) external onlyOwner {
        balancerQueries = _balancerQueries;
    }   

    /// @notice Resets WETH allowance for the specified Balancer vault.
    function resetBalancerAllowance() external onlyOwner {
        _resetWethAllowance(vault);
    }

    /// @notice Removes WETH allowance for the specified Balancer vault.
    function removeBalancerAllowance() external onlyOwner {
        _removeWethAllowance(vault);
    }

    /// @dev Converts a given amount of WETH into IMO using the specified Balancer pool.
    /// @param amount The amount of WETH to be exchanged.
    /// @param imoOutMin The minimum amount of AURA expected in return.
    function ethToImo(uint256 amount, uint256 imoOutMin, address sender, address receiver) public returns (uint256 amountOutCalculated) {

        IVault.SingleSwap memory params = IVault.SingleSwap({
            poolId: IMOpoolId,
            kind: 0, // exact input, output given
            assetIn: WETH, //Weth adress
            assetOut: IMO,
            amount: amount, // Amount to swap
            userData: ""
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: sender, // Funds are taken from this contract
            recipient: payable(receiver), // Swapped tokens are sent back to this contract
            fromInternalBalance: false, // Don't take funds from contract LPs (since there's none)
            toInternalBalance: true // Don't LP with swapped funds
        });

        amountOutCalculated = IVault(vault).swap(params, funds, imoOutMin, block.timestamp);
    }

    /// @dev Converts a given amount of USDC into ETH using the specified Balancer pool.
    /// @param amount The amount of WETH to be exchanged.
    /// @param ethOutMin The minimum amount of tokens expected in return.
    function UsdcToEth(uint256 amount, uint256 ethOutMin, address sender, address receiver) public returns (uint256 amountOutCalculated) {

        IVault.SingleSwap memory params = IVault.SingleSwap({
            poolId: IMOpoolId,
            kind: 0, // exact input, output given
            assetIn: USDC, //Weth adress
            assetOut: WETH,
            amount: amount, // Amount to swap
            userData: ""
        });

        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: sender, // Funds are taken from this contract
            recipient: payable(receiver), // Swapped tokens are sent back to this contract
            fromInternalBalance: false, // Don't take funds from contract LPs (since there's none)
            toInternalBalance: false // Don't LP with swapped funds
        });

        amountOutCalculated = IVault(vault).swap(params, funds, ethOutMin, block.timestamp);
    }

    function queryJoinImoPool(uint256 EthAmount, uint256 ImoAmount, address sender, address receiver) public returns (uint256 amountOutCalculated) {
        //ETH address for the pool is 0 (given pool is denomiated in ETH)

        IbalancerQueries.JoinPoolRequest memory request = IbalancerQueries.JoinPoolRequest({
            assets: [IMO, WETH],
            maxAmountsIn: [ImoAmount, EthAmount],
            userData: "",
            fromInternalBalance: false
        });

        IbalancerQueries.FundManagement memory funds = IbalancerQueries.FundManagement({
            sender: sender,
            recipient: payable(receiver),
            fromInternalBalance: false,
            toInternalBalance: false
        });

        (amountOutCalculated,) = IbalancerQueries(balancerQueries).queryJoin(IMOpoolId, sender, receiver, request);
    }

    function joinImoPool(uint256 EthAmount, uint256 ImoAmount, address sender, address receiver) public {
        address[] memory assets = new address[](2);
        assets[0] = WETH;  // 0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f
        assets[1] = IMO; // 0x4200000000000000000000000000000000000006

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = EthAmount;
        maxAmountsIn[1] = ImoAmount;

        bytes memory userData = abi.encode(
            uint256(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT), // = 1
            maxAmountsIn,
            uint256(0)
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: true
        });

    
        IVault(vault).joinPool(IMOpoolId, sender, receiver, request);

    }  

    function joinImoPoolImoEth(uint256 EthAmount,uint256 ImoAmount, address sender, address receiver) public {
        address[] memory assets = new address[](2);
        assets[0] = WETH;  // 0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f
        assets[1] = IMO; // 0x4200000000000000000000000000000000000006

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = EthAmount;
        maxAmountsIn[1] = ImoAmount;

        bytes memory userData = abi.encode(
            uint256(WeightedPoolUserData.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT), // = 1
            maxAmountsIn,
            uint256(0)
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

    
        IVault(vault).joinPool(IMOpoolId, sender, receiver, request);

    } 

    

    function getUserImoBalance(address user, address BPTpoolToken, uint256 BPTbalanceofUser) internal view returns (uint256) {

        uint256 totalBPTBalance = IERC20(BPTpoolToken).totalSupply();

        (address[] memory tokens, uint256[] memory balances, ) = IVault(vault).getPoolTokens(IMOpoolId);

        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == IMO) {
                return balances[i] * BPTbalanceofUser / totalBPTBalance;
            }
        }

        return 0;

    }

    // Get the IMO balance of the user in the IMO-ETH pool (hardcoded from the poolId)
    function getUserImoBalanceFromPool(uint256 BPTbalanceofUser) public view returns (uint256) {
        return getUserImoBalance(msg.sender, address(IMOETHBPT), BPTbalanceofUser);
    }
}