// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/Script.sol";

import "../src/mocks/USDC.sol";
import "../src/BaseVault.sol";
import "../src/KycManager.sol";
import "../src/FundVault.sol";

contract DeployFundVault is Script {
    using Strings for string;

    BaseVault public baseVault;
    KycManager public kycManager;
    FundVault public fundVault;
    USDC public usdc;

    function run() external {
        bool shouldDeployUSDC = vm.envOr("DEPLOY_USDC", false);
        bool shouldDeployBaseVault = vm.envOr("DEPLOY_BASE_VAULT", true);
        bool shouldDeployKycManager = vm.envOr("DEPLOY_KYC_MANAGER", true);

        string memory network = vm.envOr("NETWORK", string("localhost"));
        string memory json = vm.readFile(string.concat("./deploy/", network, ".json"));

        address CHAINLINK_TOKEN_ADDRESS = network.equal("sepolia")
            ? vm.envAddress("CHAINLINK_TOKEN_ADDRESS_SEPOLIA")
            : vm.envAddress("CHAINLINK_TOKEN_ADDRESS");
        address CHAINLINK_ORACLE_ADDRESS = network.equal("sepolia")
            ? vm.envAddress("CHAINLINK_ORACLE_ADDRESS_SEPOLIA")
            : vm.envAddress("CHAINLINK_ORACLE_ADDRESS");

        address deployer = vm.envAddress("DEPLOYER");
        vm.startBroadcast(deployer);

        if (shouldDeployUSDC) {
            usdc = new USDC();
        } else {
            usdc = USDC(vm.envAddress("USDC_ADDRESS"));
        }

        if (shouldDeployBaseVault) {
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
        } else {
            baseVault = BaseVault(vm.parseJsonAddress(json, ".BaseVault"));
        }

        kycManager =
            shouldDeployKycManager ? new KycManager(true) : KycManager(vm.parseJsonAddress(json, ".KycManager"));

        IChainlinkAccessor.ChainlinkParameters memory chainlinkParams = IChainlinkAccessor.ChainlinkParameters({
            jobId: vm.envBytes32("CHAINLINK_JOBID"),
            fee: vm.envUint("CHAINLINK_FEE"),
            urlData: vm.envString("CHAINLINK_URL_DATA"),
            pathToOffchainAssets: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS"),
            pathToTotalOffchainAssetAtLastClose: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS_AT_LAST_CLOSE")
        });

        fundVault = new FundVault(
            IERC20(address(usdc)),
            vm.envAddress("OPERATOR_ADDRESS"),
            vm.envAddress("FEE_RECEIVER_ADDRESS"),
            vm.envAddress("TREASURY_ADDRESS"),
            baseVault,
            kycManager,
            CHAINLINK_TOKEN_ADDRESS,
            CHAINLINK_ORACLE_ADDRESS,
            chainlinkParams
        );

        vm.stopBroadcast();

        // Write to json
        vm.serializeAddress(json, "BaseVault", address(baseVault));
        vm.serializeAddress(json, "KycManager", address(kycManager));
        vm.serializeAddress(json, "FundVault", address(fundVault));
        vm.serializeAddress(json, "LINK", CHAINLINK_TOKEN_ADDRESS);
        string memory finalJson = vm.serializeAddress(json, "USDC", address(usdc));
        string memory file = string.concat("./deploy/", network, ".json");
        vm.writeJson(finalJson, file);
        console.log("Contract addresses saved to %s", file);
    }
}
