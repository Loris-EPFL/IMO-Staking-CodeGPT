 IMO Staking Contracts

This repository contains the staking contracts for IMO, a Real World Asset (RWA) real estate project on the Base blockchain. The goal of the repository is to provide secure and efficient staking mechanisms for IMO tokens.

## Overview

There are two main contracts in this repository:

1. **DCBVault.sol**: Handles user interactions and the ETH zapper functionalities.
2. **DecubateMasterChef.sol**: Manages the locks for staking pools.
3. **Zapper.sol**: Handles the ETH zapper functionalities + DAO minting.

### Key Features

- **Staking Mechanism**: Uses Balancer 80 IMO / 20 ETH BPT tokens for staking.
- **Governance Token**: Mints a corresponding amount of stIMO, a non-transferable token for governance.
- **Lock Duration**: Staking pools have a lock duration and provide fixed APY for stakers.

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Tests
```shell
$ forge test -vvvv --rpc-url https://base-rpc.publicnode.com 
```

### Deploy

```shell
$ forge script script/DCBVaultDeploy.s.sol:DeployScript --rpc-url https://base-rpc.publicnode.com --private-key <your_private_key> --verify --etherscan-api-key <your_api_key> --broadcast
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
