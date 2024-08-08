// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "forge-std/Test.sol";
import "../src/DCBVault.sol";
import "../src/interfaces/IDecubateMasterChef.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract DCBVaultTest is Test {
    DCBVault public vault;
    IDecubateMasterChef public masterChef;
    IERC20 public stakeToken;
    IERC20 public rewardsToken;

    address public admin = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    function setUp() public {
        // Deploy a mock MasterChef contract
        masterChef = IDecubateMasterChef(deployCode("MockDecubateMasterChef.sol"));

        // Use the actual token addresses
        stakeToken = IERC20(0x7120fD744CA7B45517243CE095C568Fd88661c66);
        rewardsToken = IERC20(0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f);

        vault = new DCBVault(admin);
        vault.initialize(masterChef, admin);

        // Add a pool to MasterChef
        vm.prank(admin);
        masterChef.add(100, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));

        // Mint or transfer tokens to users for testing
        deal(address(stakeToken), user1, 1000 ether);
        deal(address(stakeToken), user2, 1000 ether);
    }

    function testDeposit() public {
        vm.startPrank(user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);
        vm.stopPrank();

        (uint256 shares, , uint256 totalInvested, ) = vault.users(0, user1);
        assertEq(shares, 100 ether);
        assertEq(totalInvested, 100 ether);
    }

    function testWithdraw() public {
        vm.startPrank(user1);
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
        vm.startPrank(user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 7 days);
        uint256 initialBalance = rewardsToken.balanceOf(user1);
        vault.harvest(0);
        vm.stopPrank();

        uint256 finalBalance = rewardsToken.balanceOf(user1);
        assertTrue(finalBalance > initialBalance);
    }

    function testCannotWithdrawBeforeLockPeriod() public {
        vm.startPrank(user1);
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

        vm.prank(feeReceiver);
        vault.setDepositFee(address(4), 30);
        assertEq(feeReceiver, address(4));
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
        vm.startPrank(user1);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(0, 100 ether);
        vm.stopPrank();

        uint256 pricePerFullShare = vault.getPricePerFullShare(0);
        assertEq(pricePerFullShare, 1e18);
    }
}
