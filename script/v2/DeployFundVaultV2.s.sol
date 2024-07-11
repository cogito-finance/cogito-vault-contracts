// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/Script.sol";

import "../../src/mocks/USDC.sol";
import "../../src/KycManager.sol";
import "../../src/v2/FundVaultV2.sol";

contract DeployFundVaultV2 is Script {
    using Strings for string;

    KycManager public kycManager;
    FundVaultV2 public fundVault;
    USDC public usdc;

    function run() external {
        bool shouldDeployUSDC = vm.envOr("DEPLOY_USDC", false);
        bool shouldDeployKycManager = vm.envOr("DEPLOY_KYC_MANAGER", true);

        string memory network = vm.envOr("NETWORK", string("localhost"));
        string memory json = vm.readFile(string.concat("./deploy/", network, ".json"));

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        vm.startBroadcast(deployer);

        if (shouldDeployUSDC) {
            usdc = new USDC();
        } else {
            usdc = USDC(vm.envAddress("USDC_ADDRESS"));
        }

        kycManager =
            shouldDeployKycManager ? new KycManager(true) : KycManager(vm.parseJsonAddress(json, ".KycManager"));

        fundVault = new FundVaultV2(vm.envAddress("OPERATOR_ADDRESS"), vm.envAddress("CUSTODIAN_ADDRESS"), kycManager);

        vm.stopBroadcast();

        // Write to json
        vm.serializeAddress(json, "KycManager", address(kycManager));
        vm.serializeAddress(json, "FundVaultV2", address(fundVault));
        string memory finalJson = vm.serializeAddress(json, "USDC", address(usdc));
        string memory file = string.concat("./deploy/", network, ".json");
        vm.writeJson(finalJson, file);
        console.log("Contract addresses saved to %s", file);
    }
}
