// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interfaces/Errors.sol";
import "./AdminRoleUpgradeable.sol";

abstract contract AdminOperatorRolesUpgradeable is AdminRoleUpgradeable {
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    modifier onlyAdminOrOperator() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, _msgSender()) && !hasRole(OPERATOR_ROLE, _msgSender())) {
            revert PermissionDenied();
        }
        _;
    }

    modifier onlyCaller(address receiver) {
        if (_msgSender() != receiver) {
            revert InvalidAddress(receiver);
        }
        _;
    }
}
