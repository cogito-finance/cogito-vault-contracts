// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFundVaultEvents.sol";

interface IFundVault is IFundVaultEvents {
    function fulfill(bytes32 requestId, uint256 latestOffchainNAV) external;
}
