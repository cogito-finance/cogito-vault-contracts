// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/mocks/USDC.sol";
import "../../src/KycManager.sol";
import "../../src/v3/FundVaultV3Upgradeable.sol";

contract DeployFundVaultV3Upgradeable is Script {
    using Strings for string;

    // Contract instances
    KycManager public kycManagerImplementation;
    TransparentUpgradeableProxy public kycManagerProxy;
    FundVaultV3Upgradeable public implementation;
    TransparentUpgradeableProxy public fundVaultProxy;
    USDC public usdc;

    function run() external {
        bool shouldDeployUSDC = vm.envOr("DEPLOY_USDC", false);
        bool shouldDeployKycManager = vm.envOr("DEPLOY_KYC_MANAGER", true);

        string memory network = vm.envOr("NETWORK", string("localhost"));
        string memory json = vm.readFile(
            string.concat("./deploy/", network, ".json")
        );

        address deployer = vm.envAddress("DEPLOYER_ADDRESS");
        address operator = vm.envAddress("OPERATOR_ADDRESS");
        address custodian = vm.envAddress("CUSTODIAN_ADDRESS");

        vm.startBroadcast(deployer);

        // Deploy USDC if needed
        if (shouldDeployUSDC) {
            usdc = new USDC();
        } else {
            usdc = USDC(vm.envAddress("USDC_ADDRESS"));
        }

        // Deploy or get KycManager
        if (shouldDeployKycManager) {
            // Deploy KycManager implementation
            kycManagerImplementation = new KycManager();

            // Prepare KycManager initialization data
            bytes memory kycInitData = abi.encodeWithSelector(
                KycManager.initialize.selector,
                true, // strictOn
                operator
            );

            // Deploy KycManager proxy
            kycManagerProxy = new TransparentUpgradeableProxy(
                address(kycManagerImplementation),
                deployer,
                kycInitData
            );
        } else {
            kycManagerProxy = TransparentUpgradeableProxy(
                vm.parseJsonAddress(json, ".KycManager")
            );
        }

        // Deploy FundVault implementation
        implementation = new FundVaultV3Upgradeable();

        // Prepare FundVault initialization data
        bytes memory fundVaultInitData = abi.encodeWithSelector(
            FundVaultV3Upgradeable.initialize.selector,
            operator,
            custodian,
            address(kycManagerProxy)
        );

        // Deploy FundVault proxy
        fundVaultProxy = new TransparentUpgradeableProxy(
            address(implementation),
            deployer,
            fundVaultInitData
        );

        vm.stopBroadcast();

        // Write to json

        if (shouldDeployKycManager) {
            vm.serializeAddress(
                json,
                "KycManagerImplementation",
                address(kycManagerImplementation)
            );
            vm.serializeAddress(
                json,
                "KycManagerProxy",
                address(kycManagerProxy)
            );
        }

        vm.serializeAddress(
            json,
            "FundVaultV2Implementation",
            address(implementation)
        );
        vm.serializeAddress(json, "FundVaultV2Proxy", address(fundVaultProxy));
        string memory finalJson = vm.serializeAddress(
            json,
            "USDC",
            address(usdc)
        );

        string memory file = string.concat("./deploy/", network, ".json");
        vm.writeJson(finalJson, file);
        console.log("Contract addresses saved to %s", file);
    }
}
