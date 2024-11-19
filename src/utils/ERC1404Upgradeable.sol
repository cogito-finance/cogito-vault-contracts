// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/IERC1404Upgradeable.sol";
import "../interfaces/Errors.sol";

abstract contract ERC1404Upgradeable is IERC1404Upgradeable {
    modifier notRestricted(address from, address to) {
        uint8 restrictionCode = detectTransferRestriction(from, to, 0);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
        _;
    }

    function detectTransferRestriction(address from, address to, uint256 value) public view virtual returns (uint8);

    function messageForTransferRestriction(uint8 restrictionCode) public pure returns (string memory message) {
        if (restrictionCode == SUCCESS_CODE) {
            message = SUCCESS_MESSAGE;
        } else if (restrictionCode == DISALLOWED_OR_STOP_CODE) {
            message = DISALLOWED_OR_STOP_MESSAGE;
        } else if (restrictionCode == REVOKED_OR_BANNED_CODE) {
            message = REVOKED_OR_BANNED_MESSAGE;
        }
    }
}
