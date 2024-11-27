// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


import "openzeppelin-contracts/utils/Strings.sol";
import "forge-std/Script.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "../../src/mocks/USDC.sol";
import "../../src/KycManager.sol";
import "../../src/v3/FundVaultV3Upgradeable.sol";


contract DeployFundVaultV3 is Script {
   using Strings for string;


   // Contract instances
   KycManager public kycManager;
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
       bool strictMode = vm.envOr("STRICT_MODE", true);


       vm.startBroadcast(deployer);


       // Deploy USDC if needed
       if (shouldDeployUSDC) {
           usdc = new USDC();
       } else {
           usdc = USDC(vm.envAddress("USDC_ADDRESS"));
       }


       // Deploy or get KycManager
       if (shouldDeployKycManager) {
           // Deploy KycManager (non-upgradeable)
           kycManager = new KycManager(
               strictMode
           );
       } else {
           kycManager = KycManager(
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
           address(kycManager)
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
               "KycManager",
               address(kycManager)
           );
       }


       vm.serializeAddress(
           json,
           "FundVaultV3Implementation",
           address(implementation)
       );
       vm.serializeAddress(json, "FundVaultV3Proxy", address(fundVaultProxy));
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
