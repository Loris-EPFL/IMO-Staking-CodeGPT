// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.20;

import "forge-std/Test.sol";
import "../src/DecubateMasterChef.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC721/extensions/IERC721Enumerable.sol";
import {Utils} from "./utils/Utils.sol";


contract DecubateMasterChefTest is Test {
    DecubateMasterChef public masterChef;
    IERC20 public stakeToken;
    IERC20 public rewardsToken;

    address payable[] internal users;
    address payable[] internal admins;

    Utils internal utils;
    address public admin;
    address public feeAdress;

    bytes32 balancerPoolID = 0x007bb7a4bfc214df06474e39142288e99540f2b3000200000000000000000191;
    address balancerVault = balancerVault;
    address IMO = 0x5A7a2bf9fFae199f088B25837DcD7E115CF8E1bb;
    address IMO_BPT = 0x007bb7a4bfc214DF06474E39142288E99540f2b3;
    address WETH = 0x4200000000000000000000000000000000000006;
   

    function setUp() public {

        utils = new Utils();

        admins = utils.createUsers(2);
        admin = admins[0];
        feeAdress = admins[1];

        vm.startPrank(admin);


        masterChef = new DecubateMasterChef();
        masterChef.initialize(admin);

        users = utils.createUsers(2);

        stakeToken = IERC20(IMO_BPT); // Balancer 75 IMO / 25 WETH pool token
        rewardsToken = IERC20(IMO); // IMO token


        // Assume we have a way to mint or transfer tokens to users for testing
        deal(address(stakeToken), users[0], 100 ether);
        deal(address(stakeToken), users[1], 100 ether);
        deal(address(rewardsToken), address(masterChef), 10000 ether);

        vm.stopPrank();
    }

    function testInitialization() public {
        assertTrue(masterChef.hasRole(masterChef.DEFAULT_ADMIN_ROLE(), admin));
        //assertTrue(masterChef.hasRole(masterChef.MANAGER_ROLE(), admin));
    }

    function testAddPool() public {
        vm.startPrank(admin);
        
        uint256 apy = 120; // 12%
        uint256 lockPeriodInDays = 30;
        uint256 endDate = block.timestamp + 365 days;
        uint256 hardCap = 1000 ether;

        masterChef.add(apy, lockPeriodInDays, endDate, hardCap, address(stakeToken), address(rewardsToken));

        (uint256 poolApy, uint256 poolLockPeriod, , , uint256 poolEndDate, uint256 poolHardCap, address poolStakeToken, address poolRewardsToken) = masterChef.poolInfo(0);

        assertEq(poolApy, apy);
        assertEq(poolLockPeriod, lockPeriodInDays);
        assertEq(poolEndDate, endDate);
        assertEq(poolHardCap, hardCap);
        //assertEq(poolStakeToken, address(stakeTokenEq(poolRewardsToken, address(rewardsToken));

        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 10 ether);

        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        masterChef.stake(0, 10 ether);

        (uint256 totalInvested, , , ,  ) = masterChef.users(0, users[0]);
        assertEq(totalInvested, 10 ether);

        vm.stopPrank();
    }

    function testCannotStakeMoreThanHardCap() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 100 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 101 ether);


        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 101 ether);
        vm.expectRevert("Pool full");
        masterChef.stake(0, 101 ether);
        vm.stopPrank();
    }

    function testCannotStakeAfterEndDate() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 100 ether);


        vm.warp(block.timestamp + 366 days);

        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        vm.expectRevert("Staking disabled for this pool");
        masterChef.stake(0, 100 ether);
        vm.stopPrank();
    }

    function testClaim() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days,   1000 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 100 ether);


        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        masterChef.stake(0, 100 ether);

        vm.warp(block.timestamp + 31 days);

        uint256 initialBalance = rewardsToken.balanceOf(users[0]);
        masterChef.claim(0);
        uint256 finalBalance = rewardsToken.balanceOf(users[0]);

        assertTrue(finalBalance > initialBalance);

        vm.stopPrank();
    }

    function testCannotClaimBeforeLockPeriod() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 100 ether);


        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        masterChef.stake(0, 100 ether);

        vm.warp(block.timestamp + 29 days);

        masterChef.claim(0);

        vm.stopPrank();
    }

    function testUnstake() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));
        vm.stopPrank();

        deal(address(stakeToken), users[0], 100 ether);


        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        masterChef.stake(0, 100 ether);

        vm.warp(block.timestamp + 31 days);

        uint256 initialBalance = stakeToken.balanceOf(users[0]);
        masterChef.unStake(0, 100 ether);
        uint256 finalBalance = stakeToken.balanceOf(users[0]);

        assertEq(finalBalance, initialBalance + 100 ether);

        vm.stopPrank();
    }

   

}