// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";

abstract contract AdminRoleUpgradeable is AccessControlUpgradeable {
    modifier onlyAdmin() {
        _checkRole(DEFAULT_ADMIN_ROLE);
        _;
    }
}
