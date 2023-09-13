// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITestEvents {
    event ChainlinkRequested(bytes32 indexed id);
    event ChainlinkFulfilled(bytes32 indexed id);
    event ChainlinkCancelled(bytes32 indexed id);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
