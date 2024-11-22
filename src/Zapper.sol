// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/interfaces/IERC20.sol";
import { IWETH } from "./balancer/interfaces/IWETH.sol";
import { DCBVault } from "./DCBVault.sol";
import {ABalancer} from "./balancer/zapper/ABalancer.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {IDCBVault} from "./interfaces/IDCBVault.sol";
import {IstIMO} from "./interfaces/IstIMO.sol";




contract Zapper is ABalancer {
    using SafeERC20 for IERC20;

    IERC20 public stakeTokenERC;
    IDCBVault DecubateVault;

    IstIMO public  stIMO;

    uint256 public balancerWeight = 80;


    constructor(address _bptERC20, address _DCBVault, address _stIMO, address _owner) Ownable(_owner) {
        stakeTokenERC = IERC20(_bptERC20);
        DecubateVault = IDCBVault(_DCBVault);
        stIMO = IstIMO(_stIMO);
    }

    error IncorrectAmount();

    function zapEtherAndStakeIMO(uint256 _pid) external payable returns (uint256 stakedAmount) {
        require(msg.sender != address(0), "AddressZero");
        require(msg.value > 0, "NullAmount");

        uint256 bptBalanceBefore = stakeTokenERC.balanceOf(address(this));

        uint256 EthToZap = (msg.value * 80) / 100; // 80% to zap
        uint256 EthAmount = msg.value - EthToZap; // 20% to remain as WETH

        IWETH(WETH).deposit{value: msg.value}();
        bool isVaultApproved = IWETH(WETH).approve(vault, msg.value);
        require(isVaultApproved, "NotApproved");

        require(EthToZap > 0 && EthAmount > 0, "IncorrectAmount");

        // Zap eth to IMO
        uint256 ImoAmount = ethToImo(EthToZap, 0, address(this), address(this));
        require(ImoAmount > 0, "IncorrectAmount");

        // Join IMO pool (IMO is given from Vault internal Balance, WETH is given from here)
        joinImoPool(EthAmount, ImoAmount, address(this), address(this));

        // Stake the received BPT tokens
        stakedAmount = stakeTokenERC.balanceOf(address(this)) - bptBalanceBefore; //get new BPT balance of contract
        if(stakedAmount == 0) revert IncorrectAmount();

        stakeTokenERC.safeIncreaseAllowance(address(DecubateVault), stakedAmount);

        // Call the deposit function of DCBVault
        DecubateVault.deposit(_pid, stakedAmount, msg.sender);

        return stakedAmount;
    }
    

   
}
