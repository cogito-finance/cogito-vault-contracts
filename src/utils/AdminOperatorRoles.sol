// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./AdminRole.sol";

abstract contract AdminOperatorRoles is AdminRole {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    modifier onlyAdminOrOperator() {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) || hasRole(OPERATOR_ROLE, _msgSender()), "permission denied");
        _;
    }

    modifier onlyCaller(address receiver) {
        require(_msgSender() == receiver, "receiver must be caller");
        _;
    }
}
