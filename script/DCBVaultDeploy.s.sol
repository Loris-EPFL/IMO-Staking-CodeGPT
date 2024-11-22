// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/DCBVault.sol";
import "../src/DecubateMasterChef.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";

contract DeployScript is Script {

    function setUp() public {
        //setup before deploy if needed
            /*
        owner = vm.envAddress("OWNER_ADDRESS");
        initialValue = vm.envUint("INITIAL_VALUE");

        // You can also set default values if env vars are not set
        if (owner == address(0)) {
            owner = address(this);
        }
        if (initialValue == 0) {
            initialValue = 100;
        }

        // Log some information
        console.log("Owner address:", owner);
        console.log("Initial value:", initialValue);

        */
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy DecubateMasterChef
        DecubateMasterChef masterChef = new DecubateMasterChef();
        masterChef.initialize(msg.sender);

        // Deploy DCBVault
        DCBVault vault = new DCBVault(msg.sender);
        vault.initialize(masterChef, msg.sender);

        // Set deposit fee to 0
        vault.setDepositFee(msg.sender, 0);

        // Use the actual token addresses for Base Network
        address stakeTokenAddress = 0x007bb7a4bfc214DF06474E39142288E99540f2b3;
        address rewardsTokenAddress = 0x5A7a2bf9fFae199f088B25837DcD7E115CF8E1bb;

        // Add a pool to MasterChef
        masterChef.add(
            100,
            30,
            block.timestamp + 365 days,
            1000 ether,
            stakeTokenAddress,
            rewardsTokenAddress
        );

         // Set up NFT functionality (if needed)
        // Replace with actual NFT contract address on Base Network
        //address = address(0); // Replace with actual address
        //masterChef.setNFT(0, "Base NFT", nftTokenAddress, true, 20, 1, 100);

        // Transfer initial rewards to MasterChef (if needed)
        // This assumes you have control over the rewards token
        // IERC20(rewardsTokenAddress).transfer(address(masterChef), 10000 ether);

        // Optional: Transfer ownership of contracts if needed
        // masterChef.transferOwnership(newOwnerAddress);
        // vault.transferOwnership(newOwnerAddress);

        vm.stopBroadcast();

        // Log deployed contract addresses
        console.log("DecubateMasterChef deployed at:", address(masterChef));
        console.log("DCBVault deployed at:", address(vault));
    }
}
