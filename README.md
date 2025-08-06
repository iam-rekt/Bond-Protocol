# Bond Protocol

A protocol for creating and managing bonds that can be redeemed for either USDC or asset tokens based on price conditions.

## Overview

The protocol consists of three main contracts:

### BondFactory
- Creates and manages bond programs
- Controls minting of asset tokens on bond redemption
- Maintains registry of valid bond contracts
- Ensures asset token can only be set once

### Bond
- ERC20 token representing a bond
- Users can mint bonds by depositing USDC
- Bonds can be redeemed after expiry for:
  - USDC if price is below strike price
  - Asset tokens if price is above strike price
- Uses Uniswap V3 TWAP for price oracle at expiry
- Allows owner to rescue stuck assets
- **Important**: Requires Uniswap V3 pool with ASSET as token0 and USDC as token1 for correct price calculations

### MintableERC20
- Asset token that can be minted by the bond factory
- Used for bond redemption when price conditions are met
- Implements access control for minting

## Key Features

- Fixed strike price in sqrt price X96 format
- Time-bound issuance and expiry periods
- Price-based redemption mechanism
- Configurable maximum USDC deposit
- CREATE2 deployment for deterministic addresses
- Rescue functionality for stuck assets

## Important Notes

### Uniswap Pool Requirements
The Bond contract relies on a specific token ordering in the Uniswap V3 pool:
- token0 must be the ASSET token
- token1 must be USDC
This ordering is crucial for correct price calculations at expiry and strike price comparisons.

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for development and testing.

## Environment Setup

Create a .env file with:
- RPC_URL: Base mainnet RPC URL
- PRIVATE_KEY: Deployment wallet private key
- ETHERSCAN_API: Basescan API_KEY


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

### Deploy

```shell
$ make deploy_factory_and_mintableERC20
```

### Check Deployment

```shell
$ make check_factory_and_mintableERC20
```

