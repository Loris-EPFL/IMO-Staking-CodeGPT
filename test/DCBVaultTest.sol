// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "forge-std/Test.sol";
import "../src/DCBVault.sol";
import "../src/interfaces/IDecubateMasterChef.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../src/DecubateMasterChef.sol";
import {Utils} from "./utils/Utils.sol";



contract DCBVaultTest is Test {
    DCBVault public vault;
    DecubateMasterChef public masterChef;
    IERC20 public stakeToken;
    IERC20 public rewardsToken;
    
    

    address public admin;
    address public masterChefAddress;
    address public user1;
    address public user2;
    address payable[] testsAddresses;
    Utils internal utils;

    function setUp() public {
        utils = new Utils();
        testsAddresses = utils.createUsers(4);
        admin = testsAddresses[0];
        masterChefAddress = testsAddresses[1];
        user1 = testsAddresses[2];
        user2 = testsAddresses[3];

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        // Deploy a mock MasterChef contract
        //masterChef = IDecubateMasterChef(deployCode("MockDecubateMasterChef.sol"));
        vm.prank(masterChefAddress);
        masterChef = new DecubateMasterChef();
        masterChef.initialize(admin);

        // Use the actual token addresses
        stakeToken = IERC20(0x7120fD744CA7B45517243CE095C568Fd88661c66);
        rewardsToken = IERC20(0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f);

        vault = new DCBVault(admin);
        vault.initialize(masterChef, admin);

        vault.setDepositFee(admin, 0);

        // Add a pool to MasterChef
        vm.prank(admin);
        masterChef.add(100, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));

        // Mint or transfer tokens to users for testing
        deal(address(stakeToken), user1, 1000 ether);
        deal(address(stakeToken), user2, 1000 ether);
        deal(address(rewardsToken), address(vault.masterchef()), 10000 ether);
    }

    function testDeposit() public {
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);
        vm.stopPrank();

        (uint256 shares, , uint256 totalInvested, ) = vault.users(0, user1);
        assertEq(shares, 100 ether);
        assertEq(totalInvested, 100 ether);
    }

    function testWithdraw() public {
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);

        // Warp time to after lock period
        vm.warp(block.timestamp + 31 days);

        uint256 initialBalance = stakeToken.balanceOf(user1);
        vault.withdraw(0, 100 ether);
        vm.stopPrank();

        uint256 finalBalance = stakeToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, 100 ether);
    }

    function testHarvest() public {
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 32 ether); //30 * 1e18 is 0.0036 ETH (9,44$) + 264,5 IMO (37,15$) = 46,59$
        vm.stopPrank();

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 366 days);
        vm.startPrank(user1, user1);
        //masterChef.claim(0);
        console2.log("addrss of masterchef", address(vault.masterchef()));
        console2.log("balance of masterChef", rewardsToken.balanceOf(address(vault.masterchef())));
        uint256 initialBalance = rewardsToken.balanceOf(user1);
        //console2.log("msg sender is", msg.sender);
        vault.harvest(0);
        vm.stopPrank();

        uint256 finalBalance = rewardsToken.balanceOf(user1);
        console2.log("imo harvested", (finalBalance - initialBalance) / 1e18);
        console2.log("imo harvested in $", ((finalBalance - initialBalance) * 14 / (1e18*100))); //imo price is 0,14$

        assertTrue(finalBalance > initialBalance);
    }

    function testZapEtherAndStakeIMO() public {
        uint256 pid = 0;
        uint256 zapAmount = 10e10;

        // Get initial balances
        uint256 initialEthBalance = address(user1).balance;
        uint256 initialStakeTokenBalance = stakeToken.balanceOf(user1);

        vm.startPrank(user1);
        
        // Perform the zap and stake
        uint256 stakedAmount = vault.zapEtherAndStakeIMO{value: zapAmount}(pid);
        
        vm.stopPrank();

        // Check that ETH was deducted from user's balance
        assertEq(address(user1).balance, initialEthBalance - zapAmount, "ETH balance should be reduced");

        // Check that stake tokens were received and staked
        assertTrue(stakedAmount > 0, "Staked amount should be greater than zero");
        //assertGt(stakeToken.balanceOf(address(vault)), initialStakeTokenBalance, "Vault should have received stake tokens");

        // Check user's position in the vault
        (uint256 shares, uint256 lastDepositedTime, uint256 totalInvested, ) = vault.users(pid, user1);
        assertGt(shares, 0, "User should have shares");
        assertEq(lastDepositedTime, block.timestamp, "Last deposited time should be updated");
        assertEq(totalInvested,stakedAmount, "Total invested should match staked amount");

        // Check pool info
        (uint256 totalShares, uint256 pendingClaim, ) = vault.pools(pid);
        assertGt(totalShares, 0, "Pool should have total shares");
        //assertEq(pendingClaim, stakedAmount, "Pending claim should match staked amount");
    }

    function testWithdrawAfterZap() public {


        testZapEtherAndStakeIMO();
        uint256 zapAmount = 10e10;

        // Warp time to after lock period
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(user1, user1);    
        uint256 initialBalance = stakeToken.balanceOf(user1);
        vault.withdraw(0, zapAmount);
        vm.stopPrank();

        uint256 finalBalance = stakeToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, zapAmount);

    }


    function testCannotWithdrawBeforeLockPeriod() public {
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);

        // Try to withdraw before lock period
        vm.expectRevert("Stake still locked");
        vault.withdraw(0, 100 ether);
        vm.stopPrank();
    }

    function testSetCallFee() public {
        vm.prank(admin);
        vault.setCallFee(50);
        assertEq(vault.callFee(), 50);
    }

    function testSetDepositFee() public {
        ( uint256 depositFee, address feeReceiver) = vault.fee();
        vm.prank(feeReceiver, feeReceiver);
        vault.setDepositFee(user2, 30);

        (depositFee, feeReceiver) = vault.fee();
        assertEq(feeReceiver, user2);
        assertEq(depositFee, 30);
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);
        vault.pause();
        assertTrue(vault.paused());
        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }

    function testGetPricePerFullShare() public {
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);
        vm.stopPrank();

        uint256 pricePerFullShare = vault.getPricePerFullShare(0);
        assertEq(pricePerFullShare, 1e18);
    }
}
