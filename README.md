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
forge test -vv && forge coverage --report lcov
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
NETWORK=sepolia DEPLOY_USDC=true forge script script/DeployFundVault.s.sol -f sepolia --account deployer --broadcast
```

To deploy to mainnet:

```sh
NETWORK=mainnet forge script script/DeployFundVault.s.sol -f mainnet --account deployer --broadcast
```
