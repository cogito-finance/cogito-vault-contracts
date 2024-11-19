// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IFundVaultEventsV2.sol";
import "../interfaces/IKycManager.sol";
import "../utils/AdminOperatorRolesUpgradeable.sol";
import "../utils/ERC1404Upgradeable.sol";

/**
 * Represents a fund with offchain custodian and NAV with a whitelisted set of holders
 *
 * Roles:
 * - Investors who can subscribe/redeem the fund
 * - Operators who manage day-to-day operations
 * - Admins who can handle operator tasks and change addresses
 *
 * ## Operator Workflow
 * - Call {processDeposit} after a deposit request is approved to move funds to vault
 * - Call {transferAllToCustodian} after funds are received to send to offchain custodian
 * - Call {processRedemption} after a redemption request is approved to disburse underlying funds to investor
 */
contract FundVaultV2Upgradeable is 
    Initializable, 
    ERC20Upgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable, 
    AdminOperatorRolesUpgradeable,
    ERC1404Upgradeable, 
    IFundVaultEventsV2 
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using MathUpgradeable for uint256;

    uint256 public _latestNav;
    address public _custodian;
    IKycManager public _kycManager;
    uint256 public _tvl;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address operator,
        address custodian,
        IKycManager kycManager
    ) public initializer {
        __ERC20_init("Cogito TFUND", "TFUND");
        __ReentrancyGuard_init();
        __Pausable_init();
        __AccessControl_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, operator);

        _custodian = custodian;
        _kycManager = kycManager;
        _tvl = 0;
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    ////////////////////////////////////////////////////////////
    // Admin functions: Setting addresses
    ////////////////////////////////////////////////////////////

    function setCustodian(address newAddress) external onlyAdmin {
        _custodian = newAddress;
        emit SetCustodian(newAddress);
    }

    function setKycManager(address kycManager) external onlyAdmin {
        _kycManager = IKycManager(kycManager);
        emit SetKycManager(kycManager);
    }

    ////////////////////////////////////////////////////////////
    // Admin/Operator functions
    ////////////////////////////////////////////////////////////

    function pause() external onlyAdminOrOperator {
        _pause();
    }

    function unpause() external onlyAdminOrOperator {
        _unpause();
    }

    function setFundNav(uint256 nav) external onlyAdminOrOperator {
        _latestNav = nav;
        emit SetFundNav(nav);
    }

    function processDeposit(
        address investor,
        address asset,
        uint256 amount,
        uint256 shares
    ) external onlyAdminOrOperator {
        _mint(investor, shares);
        emit ProcessDeposit(investor, asset, amount, shares);
    }

    function processRedemption(
        address investor,
        address asset,
        uint256 amount,
        uint256 shares
    ) external onlyAdminOrOperator {
        _validateRedemption(investor, shares);
        _burn(investor, shares);
        IERC20Upgradeable(asset).safeTransfer(investor, amount);

        _tvl -= amount;

        emit ProcessRedemption(investor, shares, asset, amount);
    }

    function transferAllToCustodian(address asset) external onlyAdminOrOperator {
        uint256 balance = IERC20Upgradeable(asset).balanceOf(address(this));
        transferToCustodian(asset, balance);
    }

    function transferToCustodian(address asset, uint256 amount) public onlyAdminOrOperator {
        if (_custodian == address(0)) {
            revert InvalidAddress(_custodian);
        }

        IERC20Upgradeable(asset).safeTransfer(_custodian, amount);
        emit TransferToCustodian(_custodian, asset, amount);
    }

    function mint(address user, uint256 amount) external onlyAdminOrOperator {
        _mint(user, amount);
    }

    function burnFrom(address user, uint256 amount) external onlyAdminOrOperator {
        _burn(user, amount);
    }

    ////////////////////////////////////////////////////////////
    // Public entrypoints
    ////////////////////////////////////////////////////////////

    function deposit(address asset, uint256 amount)
        public
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _kycManager.onlyKyc(msg.sender);
        _kycManager.onlyNotBanned(msg.sender);

        _validateDeposit(msg.sender, asset, amount);

        IERC20Upgradeable(asset).safeTransferFrom(msg.sender, address(this), amount);

        _tvl += amount;

        emit RequestDeposit(msg.sender, asset, amount);
        return 0;
    }

    function redeem(uint256 shares, address asset)
        public
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        _kycManager.onlyKyc(msg.sender);
        _kycManager.onlyNotBanned(msg.sender);

        _validateRedemption(msg.sender, shares);

        emit RequestRedemption(msg.sender, shares, asset);
        return 0;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        // no restrictions on minting or burning, or self-transfers
        if (from == address(0) || to == address(0) || to == address(this)) {
            return;
        }

        uint8 restrictionCode = detectTransferRestriction(from, to, 0);
        require(
            restrictionCode == SUCCESS_CODE,
            messageForTransferRestriction(restrictionCode)
        );
    }

    ////////////////////////////////////////////////////////////
    // ERC-1404 Overrides
    ////////////////////////////////////////////////////////////

    function detectTransferRestriction(
        address from,
        address to,
        uint256 /*value*/
    ) public view override returns (uint8 restrictionCode) {
        if (_kycManager.isBanned(from)) return REVOKED_OR_BANNED_CODE;
        else if (_kycManager.isBanned(to)) return REVOKED_OR_BANNED_CODE;

        if (_kycManager.isStrict()) {
            if (!_kycManager.isKyc(from)) return DISALLOWED_OR_STOP_CODE;
            else if (!_kycManager.isKyc(to)) return DISALLOWED_OR_STOP_CODE;
        } else if (_kycManager.isUSKyc(from)) {
            if (!_kycManager.isKyc(to)) return DISALLOWED_OR_STOP_CODE;
        }
        return SUCCESS_CODE;
    }

    ////////////////////////////////////////////////////////////
    // Conversion between deposits and shares
    ////////////////////////////////////////////////////////////

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply();
        return (assets == 0 || supply == 0)
            ? assets
            : assets.mulDiv(supply, _latestNav, MathUpgradeable.Rounding.Down);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? shares
            : shares.mulDiv(_latestNav, supply, MathUpgradeable.Rounding.Down);
    }

    ////////////////////////////////////////////////////////////
    // Validation
    ////////////////////////////////////////////////////////////

    function _validateDeposit(
        address user,
        address asset,
        uint256 amount
    ) internal view {
        uint256 balance = IERC20Upgradeable(asset).balanceOf(user);
        if (amount > balance) {
            revert InsufficientBalance(balance, amount);
        }
        if (IERC20Upgradeable(asset).allowance(user, address(this)) < amount) {
            revert InsufficientAllowance(
                IERC20Upgradeable(asset).allowance(user, address(this)),
                amount
            );
        }
    }

    function _validateRedemption(address user, uint256 share) internal view virtual {
        if (share > balanceOf(user)) {
            revert InsufficientBalance(balanceOf(user), share);
        }
    }

    ////////////////////////////////////////////////////////////
    // Emergency functions
    ////////////////////////////////////////////////////////////

    function _fixTVL(uint256 newTvl) external onlyAdmin {
        _tvl = newTvl;
    }

    ////////////////////////////////////////////////////////////
    // View functions
    ////////////////////////////////////////////////////////////

    function getLatestNav() external view returns (uint256) {
        return _latestNav;
    }

    function getCustodian() external view returns (address) {
        return _custodian;
    }

    function getKycManager() external view returns (IKycManager) {
        return _kycManager;
    }

    function getTvl() external view returns (uint256) {
        return _tvl;
    }
}