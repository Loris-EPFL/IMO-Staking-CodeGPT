// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

import "forge-std/Test.sol";
import "../src/DCBVault.sol";
import "../src/interfaces/IDecubateMasterChef.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "../src/DecubateMasterChef.sol";
import {Utils} from "./utils/Utils.sol";
import {IVault} from "../src/balancer/interfaces/IVault.sol";
import {IstIMO} from "../src/interfaces/IstIMO.sol";
import {Zapper} from "../src/Zapper.sol";
import {IstIMO} from "../src/interfaces/IstIMO.sol";


contract DCBVaultTest is Test {
    DCBVault public vault;
    DecubateMasterChef public masterChef;
    IstIMO public stakedIMO = IstIMO(0x2f10F5F8C3704270fe64BCf40dB8d9a78Ac97778);
    address public USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    Zapper public zapper;
    IERC20 public stakeToken;
    IERC20 public rewardsToken;

    
    struct PoolInfo {
    uint256 totalShares; // Total shares in the pool
    uint256 pendingClaim; // Claim stored when pool is full
    uint256 lastHarvestedTime; // keeps track of the last pool update
  }

    address public admin;
    address public masterChefAddress;
    address public user1;
    address public user2;
    address payable[] testsAddresses;
    Utils internal utils;
    uint256 hardcap = 100000000 ether;
    bytes32 balancerPoolID = 0x007bb7a4bfc214df06474e39142288e99540f2b3000200000000000000000191;
    address balancerVault = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address IMO = 0x5A7a2bf9fFae199f088B25837DcD7E115CF8E1bb;
    address IMO_BPT = 0x007bb7a4bfc214DF06474E39142288E99540f2b3;
    address WETH = 0x4200000000000000000000000000000000000006;
    uint256 fuzzerLowBound = 1 ether; //deposit at least 1 BPT

    function joinImoPool(uint256 EthAmount, uint256 ImoAmount, address sender, address receiver) public {
        address[] memory assets = new address[](2);
        assets[0] = WETH;  // 0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f
        assets[1] = IMO; // WETH

        uint256[] memory maxAmountsIn = new uint256[](2);
        maxAmountsIn[0] = EthAmount;
        maxAmountsIn[1] = ImoAmount;

        bytes memory userData = abi.encode(
            uint256(1), // = 1
            maxAmountsIn,
            uint256(0)
        );

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            assets: assets,
            maxAmountsIn: maxAmountsIn,
            userData: userData,
            fromInternalBalance: false
        });

    
        IVault(balancerVault).joinPool(balancerPoolID, sender, receiver, request);

    }  

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
        stakeToken = IERC20(IMO_BPT);
        rewardsToken = IERC20(IMO);

        vault = new DCBVault(admin);
        vault.initialize(masterChef, admin);

        zapper = new Zapper(IMO_BPT, address(vault), address(stakedIMO), admin);


        vm.prank(0x27E20BD50106e3Fbc50A230bd5dC02D7793c7D84);
        stakedIMO.changeStakingContract(address(vault));

        vm.prank(admin);
        vault.updateZapper(address(zapper));

        vault.setDepositFee(admin, 0);
        vm.prank(admin);
        vault.updateStakedIMO(address(stakedIMO));

        // Add a pool to MasterChef
        vm.prank(admin);
        uint256 criticalAPy = 980; //apy that causes overflow
        masterChef.add(100, 30, block.timestamp + 365 days, hardcap, address(stakeToken), address(rewardsToken));
        masterChef.add(criticalAPy, 1, block.timestamp + 365 days, hardcap, address(stakeToken), address(rewardsToken));


        // Mint or transfer tokens to users for testing
        deal(address(stakeToken), user1, 1000 ether);
        deal(address(stakeToken), user2, 1000 ether);
        deal(address(rewardsToken), address(vault.masterchef()), 100000000000000 ether);


        
        //add lot of liquidity to pool
        deal(WETH, address(this), 10 ether); //deals WETH
        deal(address(rewardsToken), address(this), 1000000 ether); //deals IMO
        IERC20(WETH).approve(balancerVault, 10 ether);
        rewardsToken.approve(balancerVault, 1000000 ether);
        //joinImoPool(10 ether, 1000000 ether, address(this), address(this));
        
    }

    

    function testDeposit(uint256 depositAmount) public {
        vm.assume(depositAmount > fuzzerLowBound);
        vm.assume(depositAmount < hardcap);
        deal(address(stakeToken), user1, depositAmount);
        uint256 poolID = 1;
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), depositAmount);
        vault.deposit(poolID, depositAmount, user1);
        vm.stopPrank();

        (uint256 shares, , uint256 totalInvested, , ) = vault.users(poolID, user1);
        assertEq(shares, depositAmount);
        assertEq(totalInvested, depositAmount);
    }

    function testWithdraw(uint256 zapAmount) public {
        vm.assume(zapAmount > fuzzerLowBound);
        vm.assume(zapAmount < hardcap);
        deal(address(stakeToken), user1, zapAmount);

        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), zapAmount);
        vault.deposit(0, zapAmount, user1);

        // Warp time to after lock period
        vm.warp(block.timestamp + 31 days);

        uint256 initialBalance = stakeToken.balanceOf(user1);
        vault.withdraw(0, zapAmount);
        vm.stopPrank();

        uint256 finalBalance = stakeToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, zapAmount);
    }

    function testHarvest(uint256 stakeAmount) public {
        vm.assume(stakeAmount > fuzzerLowBound);
        vm.assume(stakeAmount < hardcap);
        //uint256 stakeAmount = 4536 ether; //staking 4536 BPT (ABOUT 10K$) Results in 17000 IMO and 0.73 ETH
        deal(address(stakeToken), user1, stakeAmount);
        console2.log("Input value of about ", stakeAmount * 222 / (1e18*100)); //BPT price is 2,22$
        
        uint256 poolID = 0;
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault),stakeAmount);
        vault.deposit(poolID, stakeAmount, user1); //30 * 1e18 is 0.0036 ETH (9,44$) + 264,5 IMO (37,15$) = 46,59$
        vm.stopPrank();

        // Warp time to accumulate rewards
        vm.warp(block.timestamp + 366 days);
        vm.startPrank(user1, user1);
        //masterChef.claim(0);
        console2.log("addrss of masterchef", address(vault.masterchef()));
        console2.log("balance of masterChef", rewardsToken.balanceOf(address(vault.masterchef())));
        uint256 initialBalance = rewardsToken.balanceOf(user1);
        //console2.log("msg sender is", msg.sender);
        vault.harvest(poolID);
        vm.stopPrank();

        uint256 finalBalance = rewardsToken.balanceOf(user1);
        console2.log("imo harvested", (finalBalance - initialBalance) / 1e18);
        console2.log("imo harvested in $", ((finalBalance - initialBalance) * 48 / (1e18*100))); //imo price is 0,48$

        assertGe(finalBalance, initialBalance);
    }

    function testZapEtherAndStakeIMO(uint256 zapAmount) public {
        vm.assume(zapAmount > 1e8);
        vm.assume(zapAmount < 10 ether);
        vm.deal(user1, zapAmount);
        uint256 pid = 1;
        //uint256 zapAmount = 10e10;

        // Get initial balances
        uint256 initialEthBalance = address(user1).balance;
        uint256 initialStakeTokenBalance = stakeToken.balanceOf(user1);

        vm.startPrank(user1);
        
        // Perform the zap and stake
        uint256 stakedAmount = zapper.zapEtherAndStakeIMO{value: zapAmount}(pid);
        
        vm.stopPrank();

        // Check that ETH was deducted from user's balance
        assertEq(address(user1).balance, initialEthBalance - zapAmount, "ETH balance should be reduced");

        // Check that stake tokens were received and staked
        assertTrue(stakedAmount > 0, "Staked amount should be greater than zero");
        //assertGt(stakeToken.balanceOf(address(vault)), initialStakeTokenBalance, "Vault should have received stake tokens");

        // Check user's position in the vault
        (uint256 shares, uint256 lastDepositedTime, uint256 totalInvested, , ) = vault.users(pid, user1);
        assertGt(shares, 0, "User should have shares");
        assertEq(lastDepositedTime, block.timestamp, "Last deposited time should be updated");
        assertEq(totalInvested,stakedAmount, "Total invested should match staked amount");

        // Check pool info
        (uint256 totalShares, uint256 pendingClaim, ) = vault.pools(pid);
        assertGt(totalShares, 0, "Pool should have total shares");
        //assertEq(pendingClaim, stakedAmount, "Pending claim should match staked amount");
    }

    function testWithdrawAfterZap(uint256 zapAmount) public {
        vm.assume(zapAmount > 1e6);
        vm.assume(zapAmount < hardcap);
        deal(address(stakeToken), user1, zapAmount);

        testZapEtherAndStakeIMO(zapAmount);

        // Warp time to after lock period
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(user1, user1);    
        uint256 initialBalance = stakeToken.balanceOf(user1);
        vault.withdraw(1, zapAmount);
        vm.stopPrank();

        uint256 finalBalance = stakeToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, zapAmount);

    }


    function testCannotWithdrawBeforeLockPeriod(uint256 zapAmount) public {
        vm.assume(zapAmount > 0);
        vm.assume(zapAmount < hardcap);
        deal(address(stakeToken), user1, zapAmount);

        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), zapAmount);
        vault.deposit(1, zapAmount, user1);

        // Try to withdraw before lock period
        vm.expectRevert("Stake still locked");
        vault.withdraw(1, zapAmount);
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
        vault.deposit(0, 100 ether, user1);
        vm.stopPrank();

        uint256 pricePerFullShare = vault.getPricePerFullShare(0);
        assertEq(pricePerFullShare, 1e18);
    }

    function testEqualDeposits() public {
        uint256 depositAmount = 100 ether;
        uint256 POOL_ID = 0;
        deal(address(stakeToken), user1, depositAmount);
        deal(address(stakeToken), user2, depositAmount);

        vm.prank(user1, user1);
        stakeToken.approve(address(vault), depositAmount);

        vm.prank(user2, user2);
        stakeToken.approve(address(vault), depositAmount);


        // Users deposit equal amounts
        vm.prank(user1, user1);
        vault.deposit(POOL_ID, depositAmount, user1);

        vm.prank(user2, user2);
        vault.deposit(POOL_ID, depositAmount, user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Check rewards
        uint256 user1Rewards = vault.getRewardOfUser(user1, POOL_ID);
        uint256 user2Rewards = vault.getRewardOfUser(user2, POOL_ID);

        assertNotEq(user1Rewards, 0);

        assertNotEq(user2Rewards, 0);
        assertApproxEqRel(user1Rewards, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

       // Harvest rewards
        uint256 rewardsTokenUser1BeforeHarvest = rewardsToken.balanceOf(user1);

        vm.prank(user1, user1);
        vault.harvest(0);
        uint256 user1Harvested = rewardsToken.balanceOf(user1) - rewardsTokenUser1BeforeHarvest;

        assertApproxEqRel(user1Harvested, user1Rewards, 1e15); // Allow 0.1% difference due to rounding

        uint256 rewardsTokenUser2BeforeHarvest = rewardsToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.harvest(0);
        uint256 user2Harvested = rewardsToken.balanceOf(user2) - rewardsTokenUser2BeforeHarvest;

        assertApproxEqRel(user2Harvested, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

        assertApproxEqRel(user1Harvested, user2Harvested, 1e15); // Allow 0.1% difference due to rounding

        // Withdraw
        uint256 stakeTokenUser1BeforeWithdraw = stakeToken.balanceOf(user1);
        vm.prank(user1, user1);
        vault.withdraw(0, depositAmount);

        uint256 diffUser1 = stakeToken.balanceOf(user1) - stakeTokenUser1BeforeWithdraw;
        assertEq(diffUser1, depositAmount);

    
        uint256 stakeTokenUser2BeforeWithdraw = stakeToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.withdraw(0, depositAmount);

        uint256 diffUser2 = stakeToken.balanceOf(user2) - stakeTokenUser2BeforeWithdraw;
        assertEq(diffUser2, depositAmount);

        assertEq(diffUser1, diffUser2);
    }

    function testEqualDepositsFuzz(uint256 amountIn) public {
        vm.assume(amountIn > 1e5 && amountIn < hardcap /2);
        uint256 depositAmount = amountIn;
        uint256 POOL_ID = 0;
        deal(address(stakeToken), user1, depositAmount);
        deal(address(stakeToken), user2, depositAmount);

        vm.prank(user1, user1);
        stakeToken.approve(address(vault), depositAmount);

        vm.prank(user2, user2);
        stakeToken.approve(address(vault), depositAmount);


        // Users deposit equal amounts
        vm.prank(user1, user1);
        vault.deposit(POOL_ID, depositAmount, user1);

        vm.prank(user2, user2);
        vault.deposit(POOL_ID, depositAmount, user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Check rewards
        uint256 user1Rewards = vault.getRewardOfUser(user1, POOL_ID);
        uint256 user2Rewards = vault.getRewardOfUser(user2, POOL_ID);

        assertNotEq(user1Rewards, 0);

        assertNotEq(user2Rewards, 0);
        assertApproxEqRel(user1Rewards, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

       // Harvest rewards
        uint256 rewardsTokenUser1BeforeHarvest = rewardsToken.balanceOf(user1);

        vm.prank(user1, user1);
        vault.harvest(0);
        uint256 rewardsTokenUser1AfterHarvest = rewardsToken.balanceOf(user1);
        uint256 user1Harvested = rewardsTokenUser1AfterHarvest - rewardsTokenUser1BeforeHarvest;

        assertApproxEqRel(user1Harvested, user1Rewards, 1e15); // Allow 0.1% difference due to rounding

        uint256 rewardsTokenUser2BeforeHarvest = rewardsToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.harvest(0);
        uint256 rewardsTokenUser2AfterHarvest = rewardsToken.balanceOf(user2);
        uint256 user2Harvested = rewardsTokenUser2AfterHarvest - rewardsTokenUser2BeforeHarvest;

        assertApproxEqRel(user2Harvested, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

        assertApproxEqRel(user1Harvested, user2Harvested, 1e15); // Allow 0.1% difference due to rounding

        // Withdraw
        uint256 stakeTokenUser1BeforeWithdraw = stakeToken.balanceOf(user1);
        vm.prank(user1, user1);
        vault.withdraw(0, depositAmount);

        uint256 diffUser1 = stakeToken.balanceOf(user1) - stakeTokenUser1BeforeWithdraw;
        assertEq(diffUser1, depositAmount);


        uint256 stakeTokenUser2BeforeWithdraw = stakeToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.withdraw(0, depositAmount);

        uint256 diffUser2 = stakeToken.balanceOf(user2) - stakeTokenUser2BeforeWithdraw;
        assertEq(diffUser2, depositAmount);

        assertEq(diffUser1, diffUser2);
    }

    function testDifferentDeposits() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;
        uint256 POOL_ID = 0;

        deal(address(stakeToken), user1, depositAmount1);
        deal(address(stakeToken), user2, depositAmount2);

        vm.prank(user1, user1);
        stakeToken.approve(address(vault), depositAmount1);

        vm.prank(user2, user2);
        stakeToken.approve(address(vault), depositAmount2);

        // Users deposit equal amounts
        vm.prank(user1, user1);
        vault.deposit(POOL_ID, depositAmount1, user1);

        vm.prank(user2, user2);
        vault.deposit(POOL_ID, depositAmount2, user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Check rewards
        uint256 user1Rewards = vault.getRewardOfUser(user1, POOL_ID);
        uint256 user2Rewards = vault.getRewardOfUser(user2, POOL_ID);

        assertGt(user2Rewards, user1Rewards); // User2 should have more rewards
        assertApproxEqRel(user1Rewards *2, user2Rewards, 1e15); // Allow 0.1% difference between 2 times rewards of user1

        // Harvest rewards
        uint256 rewardsTokenUser1BeforeHarvest = rewardsToken.balanceOf(user1);

        vm.prank(user1, user1);
        vault.harvest(0);
        uint256 rewardsTokenUser1AfterHarvest = rewardsToken.balanceOf(user1);
        uint256 user1Harvested = rewardsTokenUser1AfterHarvest - rewardsTokenUser1BeforeHarvest;

        uint256 rewardsTokenUser2BeforeHarvest = rewardsToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.harvest(0);
        uint256 rewardsTokenUser2AfterHarvest = rewardsToken.balanceOf(user2);
        uint256 user2Harvested = rewardsTokenUser2AfterHarvest - rewardsTokenUser2BeforeHarvest;

        assertGt(user2Harvested, user1Harvested); // User2 should have more rewards
        assertApproxEqRel(user1Harvested *2 , user2Harvested, 1e15); // Allow 0.1% difference due to rounding

        // Withdraw
        uint256 stakeTokenUser1BeforeWithdraw = stakeToken.balanceOf(user1);
        vm.prank(user1, user1);
        vault.withdraw(0, depositAmount1);

        uint256 diffUser1 = stakeToken.balanceOf(user1) - stakeTokenUser1BeforeWithdraw;
        assertEq(diffUser1, depositAmount1);


        uint256 stakeTokenUser2BeforeWithdraw = stakeToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.withdraw(0, depositAmount2);

        uint256 diffUser2 = stakeToken.balanceOf(user2) - stakeTokenUser2BeforeWithdraw;
        assertEq(diffUser2, depositAmount2);

        assertGt(diffUser2, diffUser1);
    }

    function testDifferentDepositsFuzz(uint256 amountIn) public {
        vm.assume(amountIn > 1e5 && amountIn < hardcap /3);
        uint256 depositAmount1 = amountIn;
        uint256 depositAmount2 = 2* amountIn;
        uint256 POOL_ID = 0;

        deal(address(stakeToken), user1, depositAmount1);
        deal(address(stakeToken), user2, depositAmount2);

        vm.prank(user1, user1);
        stakeToken.approve(address(vault), depositAmount1);

        vm.prank(user2, user2);
        stakeToken.approve(address(vault), depositAmount2);

        // Users deposit equal amounts
        vm.prank(user1, user1);
        vault.deposit(POOL_ID, depositAmount1, user1);

        vm.prank(user2, user2);
        vault.deposit(POOL_ID, depositAmount2, user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Check rewards
        uint256 user1Rewards = vault.getRewardOfUser(user1, POOL_ID);
        uint256 user2Rewards = vault.getRewardOfUser(user2, POOL_ID);

        assertGt(user2Rewards, user1Rewards); // User2 should have more rewards
        assertApproxEqRel(user1Rewards *2, user2Rewards, 1.5 * 1e16); // Allow 1.5% difference between 2 times rewards of user1

        // Harvest rewards
        uint256 rewardsTokenUser1BeforeHarvest = rewardsToken.balanceOf(user1);

        vm.prank(user1, user1);
        vault.harvest(0);
        uint256 rewardsTokenUser1AfterHarvest = rewardsToken.balanceOf(user1);
        uint256 user1Harvested = rewardsTokenUser1AfterHarvest - rewardsTokenUser1BeforeHarvest;

        uint256 rewardsTokenUser2BeforeHarvest = rewardsToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.harvest(0);
        uint256 rewardsTokenUser2AfterHarvest = rewardsToken.balanceOf(user2);
        uint256 user2Harvested = rewardsTokenUser2AfterHarvest - rewardsTokenUser2BeforeHarvest;

        assertGt(user2Harvested, user1Harvested); // User2 should have more rewards
        assertApproxEqRel(user1Harvested *2 , user2Harvested, 1.5 * 1e16); // Allow 1.5% difference due to rounding

        // Withdraw
        uint256 stakeTokenUser1BeforeWithdraw = stakeToken.balanceOf(user1);
        vm.prank(user1, user1);
        vault.withdraw(0, depositAmount1);

        uint256 diffUser1 = stakeToken.balanceOf(user1) - stakeTokenUser1BeforeWithdraw;
        assertEq(diffUser1, depositAmount1);


        uint256 stakeTokenUser2BeforeWithdraw = stakeToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.withdraw(0, depositAmount2);

        uint256 diffUser2 = stakeToken.balanceOf(user2) - stakeTokenUser2BeforeWithdraw;
        assertEq(diffUser2, depositAmount2);

        assertGt(diffUser2, diffUser1);
    }


    function testNoRewardsAfterEndDate(uint256 stakeAmount) public {
        vm.assume(stakeAmount > fuzzerLowBound);
        vm.assume(stakeAmount < hardcap);
        deal(address(stakeToken), user1, stakeAmount);
        
        uint256 poolID = 0;
        
        // Get the pool end time
        (, , , , uint256 endTime, , , ) = masterChef.poolInfo(poolID);
        
        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), stakeAmount);
        vault.deposit(poolID, stakeAmount, user1);
        vm.stopPrank();

        // Warp time to just before the end time
        vm.warp(endTime);

        // Harvest rewards just before end time
        vm.prank(user1, user1);
        vault.harvest(poolID);
        uint256 rewardsAfterEnd = rewardsToken.balanceOf(user1);

        // Check that no additional rewards were produced after the end time
        assertGt(rewardsAfterEnd, 0, "No additional rewards should be produced after end time");

        // Try to harvest again to ensure no rewards are accumulated
        vm.warp(endTime + 40 days);
        vm.prank(user1, user1);
        vault.harvest(poolID);
        uint256 rewardsAfterHarvest = rewardsToken.balanceOf(user1);
        uint256 rewardsDiff = rewardsAfterHarvest - rewardsAfterEnd;

        assertEq(rewardsDiff, 0, "No rewards should be produced after end time");
}

    function testDepositMintsStakedIMO(uint256 amountIn) public {
        vm.assume(amountIn > 1e5 && amountIn < hardcap /2);
        uint256 depositAmount = amountIn;
        uint256 POOL_ID = 0;
        deal(address(stakeToken), user1, depositAmount);
        deal(address(stakeToken), user2, depositAmount);

        vm.prank(user1, user1);
        stakeToken.approve(address(vault), depositAmount);

        vm.prank(user2, user2);
        stakeToken.approve(address(vault), depositAmount);


        // Users deposit equal amounts
        vm.prank(user1, user1);
        vault.deposit(POOL_ID, depositAmount, user1);

        vm.prank(user2, user2);
        vault.deposit(POOL_ID, depositAmount, user2);

        // Advance time
        vm.warp(block.timestamp + 365 days);

        // Check rewards
        uint256 user1Rewards = vault.getRewardOfUser(user1, POOL_ID);
        uint256 user2Rewards = vault.getRewardOfUser(user2, POOL_ID);

        assertNotEq(user1Rewards, 0);

        assertNotEq(user2Rewards, 0);
        assertApproxEqRel(user1Rewards, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

       // Harvest rewards
        uint256 rewardsTokenUser1BeforeHarvest = rewardsToken.balanceOf(user1);

        vm.prank(user1, user1);
        vault.harvest(0);
        uint256 rewardsTokenUser1AfterHarvest = rewardsToken.balanceOf(user1);
        uint256 user1Harvested = rewardsTokenUser1AfterHarvest - rewardsTokenUser1BeforeHarvest;

        assertApproxEqRel(user1Harvested, user1Rewards, 1e15); // Allow 0.1% difference due to rounding

        uint256 rewardsTokenUser2BeforeHarvest = rewardsToken.balanceOf(user2);
        vm.prank(user2, user2);
        vault.harvest(0);
        uint256 rewardsTokenUser2AfterHarvest = rewardsToken.balanceOf(user2);
        uint256 user2Harvested = rewardsTokenUser2AfterHarvest - rewardsTokenUser2BeforeHarvest;

        assertApproxEqRel(user2Harvested, user2Rewards, 1e15); // Allow 0.1% difference due to rounding

        assertApproxEqRel(user1Harvested, user2Harvested, 1e15); // Allow 0.1% difference due to rounding

        // Check stakedIMO balances
        uint256 stakedIMOUser1 = zapper.getUserImoBalanceFromPool(depositAmount) *100 / 80;
        uint256 stakedIMOUser2 = zapper.getUserImoBalanceFromPool(depositAmount)  *100 / 80;



        assertEq(stakedIMO.balanceOf(user1), stakedIMOUser1, "Staked IMO not minted correctly");
        assertEq(stakedIMO.balanceOf(user2), stakedIMOUser2, "Staked IMO not minted correctly");

        vm.prank(user1, user1);
        vm.expectRevert();
        stakedIMO.transfer(user2, stakedIMOUser1);


    }

    function testWithdrawBurnsStakedIMO(uint256 stakedAmount) public {
        testWithdraw(stakedAmount);
        assertEq(stakedIMO.balanceOf(user1), 0, "Staked IMO not burned correctly");
    }

    

    function testMultipleDepositsAndWithdrawals() public {
        uint256 depositAmount1 = 50 ether;
        uint256 depositAmount2 = 30 ether;
        uint256 PID = 0;

        // Deal tokens to user1
        deal(address(stakeToken), user1, depositAmount1 + depositAmount2);

        vm.startPrank(user1, user1);
        stakeToken.approve(address(vault), depositAmount1 + depositAmount2);

        // First deposit
        vault.deposit(PID, depositAmount1, user1);
        
        // Second deposit
        vault.deposit(PID, depositAmount2, user1);

        // Check stakedIMO balances
        uint256 stakedIMOUser1 = zapper.getUserImoBalanceFromPool(depositAmount1)  *100 / 80;
        uint256 stakedIMOUser2 = zapper.getUserImoBalanceFromPool(depositAmount2)  *100 / 80;

        assertEq(stakedIMO.balanceOf(user1), stakedIMOUser1 + stakedIMOUser2, "Staked IMO not minted correctly for multiple deposits");

        // Warp time forward by 31 days before first withdrawal
        vm.warp(block.timestamp + 31 days);

        uint256 initialBalance = stakeToken.balanceOf(user1);

        // Partial withdrawal
        (uint256 shares,,,,) = vault.users(PID, user1);
        vault.withdraw(PID, depositAmount1);

        uint256 midBalance = stakeToken.balanceOf(user1);
        //assertEq(midBalance - initialBalance, (depositAmount1 + depositAmount2) / 2, "Partial withdrawal amount incorrect");

        console2.log("rewards balance of masterchef", rewardsToken.balanceOf(address(vault.masterchef())));
        console2.log("rewards balance of DCBVAult", rewardsToken.balanceOf(address(vault)));

        //Weird shit hapens on 2 consecutive withdrawals, need to check it more
        deal(address(rewardsToken), address(vault), 100000000000000 ether);

        (uint256 totalShares, , ) = vault.pools(PID);
        (uint256 userShares, ,, , ) = vault.users(PID, user1);

        console2.log("pool total shares", totalShares);
        console2.log("user total shares", userShares);
        /*
        uint256 accumulatedRewards = vault.accumulatedRewardsPerShare(PID);
        console2.log("accumulatedRewards", accumulatedRewards);
        */

        // Full withdrawal of remaining balance
        vault.withdraw(PID, depositAmount2);
        vm.stopPrank();

        

        uint256 finalBalance = stakeToken.balanceOf(user1);
        assertEq(finalBalance - initialBalance, depositAmount1 + depositAmount2, "Full withdrawal amount incorrect");
        assertEq(stakedIMO.balanceOf(user1), 0, "Staked IMO not burned correctly for final withdrawal");
}


    function testZapImoAndEtherAndStakeIMO(uint256 _imoAmount) public {
        vm.assume(_imoAmount > 1e18 && _imoAmount < 1e24);
        
        uint256 pid = 0;
        uint256 imoAmount = _imoAmount;
        uint256 ethAmount = _imoAmount / 2857;

        deal(user1, ethAmount);
        deal(address(rewardsToken), user1, _imoAmount);
        vm.startPrank(user1, user1);
        

        // Approve IMO transfer
        IERC20(IMO).approve(address(zapper), imoAmount);

        // User sends ETH and IMO to zap and stake
        uint256 stakedAmount = zapper.zapImoAndEtherAndStakeIMO{value: ethAmount}(pid, imoAmount);

        vm.warp(block.timestamp + 366 days);

        vault.harvest(pid);
        uint256 rewardsAfterEnd = rewardsToken.balanceOf(user1);

        // Check that no additional rewards were produced after the end time

        // Check if the staked amount is correct
        (uint256 shares, , uint256 totalInvested, , ) = vault.users(pid, user1);
        assertGt(stakedAmount, 0, "Staked amount should be greater than 0");
        assertGt(shares, 0, "Shares should be greater than 0");

        vm.stopPrank();
    }

    function testZapUSDCAndStakeIMO(uint256 usdcAmount) public {
        vm.assume(usdcAmount > 1e5 && usdcAmount < 1e18);

        deal(address(USDC), user1, usdcAmount);
        vm.startPrank(user1);
        uint256 pid = 0;
        
        

        // Approve IMO transfer
        IERC20(USDC).approve(address(zapper), usdcAmount);

        // User sends ETH and IMO to zap and stake
        uint256 stakedAmount = zapper.zapUSDCAndStakeIMO(pid, usdcAmount);

        vm.warp(block.timestamp + 366 days);

        vault.harvest(pid);
        uint256 rewardsAfterEnd = rewardsToken.balanceOf(user1);

        // Check that no additional rewards were produced after the end time

        // Check if the staked amount is correct
        (uint256 shares, , uint256 totalInvested, , ) = vault.users(pid, user1);
        assertGt(stakedAmount, 0, "Staked amount should be greater than 0");
        assertGt(shares, 0, "Shares should be greater than 0");

        vm.stopPrank();
    }
}






