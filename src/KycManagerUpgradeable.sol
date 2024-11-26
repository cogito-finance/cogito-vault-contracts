// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import './interfaces/IKycManager.sol';
import './utils/upgrades/AdminOperatorRolesUpgradeable.sol';

/**
 * Handles address permissions. An address can be KYCed for US or non-US purposes. Additionally, an address may be banned
 */
contract KycManagerUpgradeable is IKycManager, Initializable, AdminOperatorRolesUpgradeable {
    mapping(address => User) private userData;
    address[] private userList;
    uint16 private userCount;
    bool private strictOn;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(bool _strictOn, address operator) public initializer {
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, operator);
        strictOn = _strictOn;
        userCount = 0;
    }

    modifier onlyNonZeroAddress(address _investor) {
        if (_investor == address(0)) {
            revert InvalidAddress(_investor);
        }
        _;
    }

    ////////////////////////////////////////////////////////////
    // Grant
    ////////////////////////////////////////////////////////////

    function bulkGrantKyc(
        address[] calldata _investors,
        KycType[] calldata _kycTypes
    ) external onlyAdminOrOperator {
        require(_investors.length == _kycTypes.length, 'invalid input');
        for (uint256 i = 0; i < _investors.length; i++) {
            _grantKyc(_investors[i], _kycTypes[i]);
        }
    }

    function _grantKyc(address _investor, KycType _kycType) internal onlyNonZeroAddress(_investor) {
        require(KycType.US_KYC == _kycType || KycType.GENERAL_KYC == _kycType, 'invalid kyc type');

        _addUserIfNotExist(_investor);
        userData[_investor].kycType = _kycType;
        emit GrantKyc(_investor, _kycType);
    }

    ////////////////////////////////////////////////////////////
    // Revoke
    ////////////////////////////////////////////////////////////

    function bulkRevokeKyc(address[] calldata _investors) external onlyAdminOrOperator {
        for (uint256 i = 0; i < _investors.length; i++) {
            _revokeKyc(_investors[i]);
        }
    }

    function _revokeKyc(address _investor) internal onlyNonZeroAddress(_investor) {
        _addUserIfNotExist(_investor);
        User storage user = userData[_investor];
        emit RevokeKyc(_investor, user.kycType);
        user.kycType = KycType.NON_KYC;
    }

    ////////////////////////////////////////////////////////////
    // Ban
    ////////////////////////////////////////////////////////////

    function bulkBan(address[] calldata _investors) external onlyAdminOrOperator {
        for (uint256 i = 0; i < _investors.length; i++) {
            _setBanned(_investors[i], true);
        }
    }

    ////////////////////////////////////////////////////////////
    // Unban
    ////////////////////////////////////////////////////////////

    function bulkUnBan(address[] calldata _investors) external onlyAdminOrOperator {
        for (uint256 i = 0; i < _investors.length; i++) {
            _setBanned(_investors[i], false);
        }
    }

    function _setBanned(address _investor, bool _status) internal onlyNonZeroAddress(_investor) {
        userData[_investor].isBanned = _status;
        emit Banned(_investor, _status);
    }

    function setStrict(bool _status) external onlyAdminOrOperator {
        strictOn = _status;
        emit SetStrict(_status);
    }

    ////////////////////////////////////////////////////////////
    // Public getters
    ////////////////////////////////////////////////////////////

    function getUserInfo(address _investor) external view returns (User memory user) {
        user = userData[_investor];
    }

    function getAllUsers() external view returns (address[] memory) {
        return userList;
    }

    function getAllUserInfo() external view returns (UserAddress[] memory info) {
        info = new UserAddress[](userCount);
        for (uint16 i = 0; i < userCount; i++) {
            address user = userList[i];
            User storage data = userData[user];
            info[i].user = user;
            info[i].kycType = data.kycType;
            info[i].isBanned = data.isBanned;
        }
        return info;
    }

    function onlyNotBanned(address _investor) external view {
        if (userData[_investor].isBanned) {
            revert UserBanned(_investor);
        }
    }

    function onlyKyc(address _investor) external view {
        if (KycType.NON_KYC == userData[_investor].kycType) {
            revert UserMissingKyc(_investor);
        }
    }

    function isBanned(address _investor) external view returns (bool) {
        return userData[_investor].isBanned;
    }

    function isKyc(address _investor) external view returns (bool) {
        return KycType.NON_KYC != userData[_investor].kycType;
    }

    function isUSKyc(address _investor) external view returns (bool) {
        return KycType.US_KYC == userData[_investor].kycType;
    }

    function isNonUSKyc(address _investor) external view returns (bool) {
        return KycType.GENERAL_KYC == userData[_investor].kycType;
    }

    function isStrict() external view returns (bool) {
        return strictOn;
    }

    function _addUserIfNotExist(address user) internal {
        if (!userData[user].exists) {
            userList.push(user);
            userData[user].exists = true;
            ++userCount;
        }
    }
}
