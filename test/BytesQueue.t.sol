// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/utils/BytesQueue.sol";

contract BytesQueueTest is Test {
    using BytesQueue for BytesQueue.BytesDeque;

    BytesQueue.BytesDeque queue;

    function setUp() public {}

    function pushBack(address investor, uint256 shares) public {
        bytes memory data = abi.encode(investor, shares);
        queue.pushBack(data);
    }

    function popAll() public returns (address investor, uint256 shares) {
        for (; !queue.empty();) {
            bytes memory data = queue.popFront();
            (investor, shares) = abi.decode(data, (address, uint256));
        }
    }

    function getByIndex(uint256 index) public view returns (address investor, uint256 shares) {
        bytes memory data = bytes(queue.at(index));
        (investor, shares) = abi.decode(data, (address, uint256));
    }

    function test_PushPop1() public {
        address investor1 = address(this);
        uint256 shares1 = 100_000;
        pushBack(investor1, shares1);
        bytes memory data2 = queue.popFront();
        (address investor2, uint256 shares2) = abi.decode(data2, (address, uint256));
        assertEq(investor1, investor2);
        assertEq(shares1, shares2);
    }

    function test_PushPopMulti() public {
        uint256 base = 100_000;
        for (uint256 index = 1; index <= 10; index++) {
            pushBack(address(uint160(index)), base * index);
        }
        assertEq(queue.length(), 10);

        bytes memory data;
        address investor;
        uint256 shares;
        for (uint256 index = 1; !queue.empty(); index++) {
            data = queue.popFront();
            (investor, shares) = abi.decode(data, (address, uint256));
            assertEq(uint256(uint160(investor)), index);
            assertEq(shares, base * index);
        }
    }
}
