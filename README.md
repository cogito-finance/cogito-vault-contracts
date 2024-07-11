# Cogito Protocol Contracts

- Fund vaults follow the [ERC-4626](https://ethereum.org/en/developers/docs/standards/tokens/erc-4626/) standard.
- Uses latest OpenZeppelin and Chainlink libraries

## Development

First, [install Foundry](https://book.getfoundry.sh/getting-started/installation).

Copy and update a `.env` file:

```sh
cp .env.example .env
```

To build and test:

```sh
forge build
forge test && forge coverage --report lcov
```

## Key Management

There are two roles, the admin (deployer) and multiple operators. Private keys can be imported as follows:

```sh
cast wallet import -i operator
cast wallet import -i deployer
```

## Deployment

To deploy to sepolia:

```sh
NETWORK=sepolia DEPLOY_USDC=true forge script script/v2/DeployFundVaultV2.s.sol -f sepolia --account deployer --broadcast
```

To deploy to mainnet:

```sh
NETWORK=mainnet forge script script/v2/DeployFundVaultV2.s.sol -f mainnet --account deployer --broadcast
```

Verify on etherscan:

```sh
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256)" 15 100000000000 10000000000 1000000000000000 0 1000000000000000 5 0 0) --compiler-version v0.8.19+commit.7dd6d404 0xdaFec86d96F8a97f34186f9988Ead7991CBc2dd4 src/BaseVault.sol:BaseVault
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(bool)" true) --compiler-version v0.8.19+commit.7dd6d404 0x908f368431B2A9d2D26E2d9984b8c81e37E4FAEc src/KycManager.sol:KycManager
```
