// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/security/Pausable.sol";
import "openzeppelin-contracts/security/ReentrancyGuard.sol";
import "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";

import "./interfaces/IFundVaultEventsV2.sol";
import "../interfaces/IKycManager.sol";
import "../utils/AdminOperatorRoles.sol";
import "../utils/ERC1404.sol";

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
contract FundVaultV2 is ERC20, ReentrancyGuard, Pausable, AdminOperatorRoles, ERC1404, IFundVaultEventsV2 {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 public _latestNav;
    address public _custodian;
    IKycManager public _kycManager;

    ////////////////////////////////////////////////////////////
    // Init
    ////////////////////////////////////////////////////////////

    constructor(address operator, address custodian, IKycManager kycManager) ERC20("Cogito TFUND", "TFUND") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, operator);

        _custodian = custodian;
        _kycManager = kycManager;
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

    /**
     * Call after each NAV update has been published, in order to update {_latestNav}.
     */
    function setFundNav(uint256 nav) external onlyAdminOrOperator {
        _latestNav = nav;
        emit SetFundNav(nav);
    }

    /**
     * Transfers assets from investor to vault
     */
    function processDeposit(address investor, address asset, uint256 amount, uint256 shares)
        external
        onlyAdminOrOperator
    {
        _validateDeposit(investor, asset, amount);
        IERC20(asset).safeTransferFrom(investor, address(this), amount);
        _mint(investor, shares);
        emit ProcessDeposit(investor, asset, amount);
    }

    /**
     * Transfers assets from investor to vault
     */
    function processRedemption(address investor, uint256 shares, address asset, uint256 amount)
        external
        onlyAdminOrOperator
    {
        _validateRedemption(investor, shares);
        _burn(investor, shares);
        IERC20(asset).safeTransfer(investor, amount);
        emit ProcessRedemption(investor, shares, asset, amount);
    }

    /**
     * Sweeps all asset to {_custodian}
     */
    function transferAllToCustodian(address asset) external onlyAdminOrOperator {
        uint256 balance = IERC20(asset).balanceOf(address(this));
        transferToCustodian(asset, balance);
    }

    /**
     * Transfers asset to {_custodian}.
     */
    function transferToCustodian(address asset, uint256 amount) public onlyAdminOrOperator {
        if (_custodian == address(0)) {
            revert InvalidAddress(_custodian);
        }

        IERC20(asset).safeTransfer(_custodian, amount);
        emit TransferToCustodian(_custodian, asset, amount);
    }

    /**
     * Issues fund tokens to the user.
     */
    function mint(address user, uint256 amount) external onlyAdminOrOperator {
        _mint(user, amount);
    }

    /**
     * Burns fund tokens from the user.
     */
    function burnFrom(address user, uint256 amount) external onlyAdminOrOperator {
        _burn(user, amount);
    }

    ////////////////////////////////////////////////////////////
    // Public entrypoints
    ////////////////////////////////////////////////////////////

    /**
     * Request a subscription to the fund
     * @param asset Asset to deposit
     * @param amount Amount of {asset} to subscribe
     */
    function deposit(address asset, uint256 amount) public nonReentrant whenNotPaused returns (uint256) {
        _kycManager.onlyKyc(msg.sender);
        _kycManager.onlyNotBanned(msg.sender);

        _validateDeposit(msg.sender, asset, amount);

        emit RequestDeposit(msg.sender, asset, amount);
        return 0;
    }

    /**
     * Request redemption of exact shares
     * @param shares Amount of shares to redeem
     * @param asset Underlying asset to receive
     */
    function redeem(uint256 shares, address asset) public nonReentrant whenNotPaused returns (uint256) {
        _kycManager.onlyKyc(msg.sender);
        _kycManager.onlyNotBanned(msg.sender);

        _validateRedemption(msg.sender, shares);

        emit RequestRedemption(msg.sender, shares, asset);
        return 0;
    }

    /**
     * Applies KYC checks on transfers. Sender/receiver cannot be banned.
     * If strict, check both sender/receiver.
     * If sender is US, check receiver.
     * @dev will be called during: transfer, transferFrom, mint, burn
     */
    function _beforeTokenTransfer(address from, address to, uint256) internal view override {
        // no restrictions on minting or burning, or self-transfers
        if (from == address(0) || to == address(0) || to == address(this)) {
            return;
        }

        uint8 restrictionCode = detectTransferRestriction(from, to, 0);
        require(restrictionCode == SUCCESS_CODE, messageForTransferRestriction(restrictionCode));
    }

    ////////////////////////////////////////////////////////////
    // ERC-1404 Overrides
    ////////////////////////////////////////////////////////////

    function detectTransferRestriction(address from, address to, uint256 /*value*/ )
        public
        view
        override
        returns (uint8 restrictionCode)
    {
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
        return (assets == 0 || supply == 0) ? assets : assets.mulDiv(supply, _latestNav, Math.Rounding.Down);
    }

    function previewRedeem(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply();
        return (supply == 0) ? shares : shares.mulDiv(_latestNav, supply, Math.Rounding.Down);
    }

    ////////////////////////////////////////////////////////////
    // Validation
    ////////////////////////////////////////////////////////////

    /**
     * Ensures deposit amount is okay
     */
    function _validateDeposit(address user, address asset, uint256 amount) internal view {
        // gas saving by defining local variable
        uint256 balance = IERC20(asset).balanceOf(user);
        if (amount > balance) {
            revert InsufficientBalance(balance, amount);
        }
        if (IERC20(asset).allowance(user, address(this)) < amount) {
            revert InsufficientAllowance(IERC20(asset).allowance(user, address(this)), amount);
        }
    }

    /**
     * Ensures redemption amount is okay
     */
    function _validateRedemption(address user, uint256 share) internal view virtual {
        if (share > balanceOf(user)) {
            revert InsufficientBalance(balanceOf(user), share);
        }
    }
}
