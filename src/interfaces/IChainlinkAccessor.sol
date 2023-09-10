// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Action.sol";

interface IChainlinkAccessor {
    struct ChainlinkParameters {
        bytes32 jobId;
        uint256 fee;
        string urlData;
        string pathToOffchainAssets;
        string pathToTotalOffchainAssetAtLastClose;
    }

    struct RequestData {
        address investor;
        uint256 amount;
        Action action;
    }

    event SetChainlinkOracleAddress(address newAddress);
    event SetChainlinkJobId(bytes32 jobId);
    event SetChainlinkFee(uint256 fee);
    event SetChainlinkURLData(string url);
    event SetPathToOffchainAssets(string path);
    event SetPathToTotalOffchainAssetAtLastClose(string path);
}
