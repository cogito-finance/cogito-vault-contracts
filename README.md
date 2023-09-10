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
forge test -vv
```
