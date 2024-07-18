# Cogito Protocol Contracts (V2)

Represents a fund with offchain custodian and NAV, with a whitelisted set of holders.

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
export KYC_MANAGER_ADDRESS=0x908f368431B2A9d2D26E2d9984b8c81e37E4FAEc
export FUND_VAULT_ADDRESS=0xAf2d8b3075dC237E2ebC620555Dce941ED1B86c2
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(bool)" true) --compiler-version v0.8.19+commit.7dd6d404 $KYC_MANAGER_ADDRESS src/KycManager.sol:KycManager
forge verify-contract --chain-id 1 --num-of-optimizations 200 --watch --constructor-args $(cast abi-encode "constructor(address,address,address)" $OPERATOR_ADDRESS $CUSTODIAN_ADDRESS $KYC_MANAGER_ADDRESS) --compiler-version v0.8.19+commit.7dd6d404 $FUND_VAULT_ADDRESS src/v2/FundVaultV2.sol:FundVaultV2
```

## Contract Deployments

Addresses can be found in [/deploy](/deploy).
