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
    IERC721Enumerable public nftToken;

    address payable[] internal users;
    address payable[] internal admins;

    Utils internal utils;
    address public admin;
    address public feeAdress;
   

    function setUp() public {

        utils = new Utils();

        admins = utils.createUsers(2);
        admin = admins[0];
        feeAdress = admins[1];

        vm.startPrank(admin);


        masterChef = new DecubateMasterChef();
        masterChef.initialize(admin);

        users = utils.createUsers(2);

        stakeToken = IERC20(0x7120fD744CA7B45517243CE095C568Fd88661c66); // Balancer 75 IMO / 25 WETH pool token
        rewardsToken = IERC20(0x0f1D1b7abAeC1Df25f2C4Db751686FC5233f6D3f); // IMO token

        // Deploy a mock NFT contract for testing
        nftToken = IERC721Enumerable(address(new MockERC721("NFT Token", "NFT")));

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

        vm.expectRevert("Reward still locked");
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

    function NFTMultiplier() public {
        vm.startPrank(admin);
        masterChef.add(120, 30, block.timestamp + 365 days, 1000 ether, address(stakeToken), address(rewardsToken));
        masterChef.setNFT(0, "Test NFT", address(nftToken), true, 20, 1, 100);
        vm.stopPrank();

        deal(address(stakeToken), users[0], 100 ether);


        MockERC721(address(nftToken)).mint(users[0], 1);

        vm.startPrank(users[0]);
        stakeToken.approve(address(masterChef), 100 ether);
        masterChef.stake(0, 100 ether);

        vm.warp(block.timestamp + 31 days);

        uint256 rewardWithNFT = masterChef.payout(0, users[0]);
        
        vm.stopPrank();

        MockERC721(address(nftToken)).transferFrom(users[0], address(this), 1);

        uint256 rewardWithoutNFT = masterChef.payout(0, users[0]);

        assertTrue(rewardWithNFT > rewardWithoutNFT);
    }
}

// Mock ERC721 contract for testing
contract MockERC721 is IERC721Enumerable {
    string public name;
    string public symbol;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _owners;
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;
    mapping(uint256 => uint256) private _ownedTokensIndex;
    uint256[] private _allTokens;
    mapping(uint256 => uint256) private _allTokensIndex;

    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }

    function mint(address to, uint256 tokenId) public {
        //_mint(to, tokenId);
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _balances[to] += 1;
        _owners[tokenId] = to;

        uint256 length = _balances[to];
        _ownedTokens[to][length - 1] = tokenId;
        _ownedTokensIndex[tokenId] = length - 1;

        _allTokens.push(tokenId);
        _allTokensIndex[tokenId] = _allTokens.length - 1;
    
    }

    function balanceOf(address owner) public view override returns (uint256) {
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    function tokenOfOwnerByIndex(address owner, uint256 index) public view override returns (uint256) {
        require(index < balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    function totalSupply() public view override returns (uint256) {
        return _allTokens.length;
    }

    function tokenByIndex(uint256 index) public view override returns (uint256) {
        require(index < totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    // Implement other IERC721 and IERC721Enumerable functions as needed for testing
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public override {}
    function safeTransferFrom(address from,address to,uint256 tokenId) public override {}
    function transferFrom(address from, address to, uint256 tokenId) public override {}
    function approve(address to, uint256 tokenId) public override {}
    function getApproved(uint256 tokenId) public view override returns (address) {}
    function setApprovalForAll(address operator, bool approved) public override {}
    function isApprovedForAll(address owner, address operator) public view override returns (bool) {}
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {}
}
