// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import "../src/BaseVault.sol";
import "../src/KycManager.sol";
import "../src/FundVault.sol";

contract DeployFundVault is Script {
    BaseVault public baseVault;
    KycManager public kycManager;
    FundVault public fundVault;

    function run() external {
        baseVault = new BaseVault(
            vm.envUint("TRANSACTION_FEE"),
            vm.envUint("INITIAL_DEPOSIT"),
            vm.envUint("MIN_DEPOSIT"),
            vm.envUint("MAX_DEPOSIT"),
            vm.envUint("MIN_WITHDRAW"),
            vm.envUint("MAX_WITHDRAW"),
            vm.envUint("TARGET_RESERVE_LEVEL"),
            vm.envUint("ONCHAIN_SERVICE_FEE_RATE"),
            vm.envUint("OFFCHAIN_SERVICE_FEE_RATE")
        );

        kycManager = new KycManager();

        IChainlinkAccessor.ChainlinkParameters memory chainlinkParams = IChainlinkAccessor.ChainlinkParameters({
            jobId: vm.envBytes32("CHAINLINK_JOBID"),
            fee: vm.envUint("CHAINLINK_FEE"),
            urlData: vm.envString("CHAINLINK_URL_DATA"),
            pathToOffchainAssets: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS"),
            pathToTotalOffchainAssetAtLastClose: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS_AT_LAST_CLOSE")
        });

        fundVault = new FundVault();
        fundVault.initialize(
            IERC20Upgradeable(vm.envAddress("USDC_ADDRESS")),
            vm.envAddress("OPERATOR_ADDRESS"),
            vm.envAddress("FEE_RECEIVER_ADDRESS"),
            vm.envAddress("TREASURY_ADDRESS"),
            baseVault,
            kycManager,
            vm.envAddress("CHAINLINK_TOKEN_ADDRESS"),
            vm.envAddress("CHAINLINK_ORACLE_ADDRESS"),
            chainlinkParams
        );
    }
}
