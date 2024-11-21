// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";

import "../../src/mocks/USDC.sol";
import "../../src/KycManager.sol";
import "../../src/v3/FundVaultV3Upgradeable.sol";

contract DeployFundVaultV3Upgradeable is Script {
    using Strings for string;

    KycManager public kycManager;
    FundVaultV3Upgradeable public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    USDC public usdc;

    function run() external {
        bool shouldDeployUSDC = vm.envOr("DEPLOY_USDC", false);
        bool shouldDeployKycManager = vm.envOr("DEPLOY_KYC_MANAGER", true);

        string memory network = vm.envOr("NETWORK", string("localhost"));
        string memory json = vm.readFile(string.concat("./deploy/", network, ".json"));

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
        kycManager = 
            shouldDeployKycManager ? new KycManager(true) : KycManager(vm.parseJsonAddress(json, ".KycManager"));

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin();

        // Deploy implementation
        implementation = new FundVaultV3Upgradeable();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            FundVaultV3Upgradeable.initialize.selector,
            operator,
            custodian,
            kycManager
        );

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        vm.stopBroadcast();

        // Write to json
        vm.serializeAddress(json, "KycManager", address(kycManager));
        vm.serializeAddress(json, "FundVaultV2Implementation", address(implementation));
        vm.serializeAddress(json, "FundVaultV2Proxy", address(proxy));
        vm.serializeAddress(json, "ProxyAdmin", address(proxyAdmin));
        string memory finalJson = vm.serializeAddress(json, "USDC", address(usdc));
        
        string memory file = string.concat("./deploy/", network, ".json");
        vm.writeJson(finalJson, file);
        console.log("Contract addresses saved to %s", file);
    }
}