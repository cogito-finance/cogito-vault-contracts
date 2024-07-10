// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Script.sol";
import "../../src/v1/FundVault.sol";

contract AdvanceEpochScript is Script {
    function run() external {
        string memory network = vm.envOr("NETWORK", string("localhost"));
        string memory json = vm.readFile(string.concat("./deploy/", network, ".json"));
        address fundVaultAddress = vm.parseJsonAddress(json, ".FundVault");
        FundVault fundVault = FundVault(fundVaultAddress);

        uint256 operatorPrivateKey = vm.envUint("OPERATOR_PRIVATE_KEY");
        vm.startBroadcast(operatorPrivateKey);
        fundVault.requestAdvanceEpoch();
        vm.stopBroadcast();
    }
}
