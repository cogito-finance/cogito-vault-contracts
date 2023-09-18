// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts-upgradeable/security/PausableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";

import "./ChainlinkAccessor.sol";
import "./interfaces/IBaseVault.sol";
import "./interfaces/IFundVault.sol";
import "./interfaces/IKycManager.sol";
import "./utils/AdminOperatorRoles.sol";
import "./utils/BytesQueue.sol";
import "./utils/ERC1404.sol";

/**
 * Represents a fund vault with offchain NAV and onchain assets for liquidity.
 *
 * Roles:
 * - Investors who can subscribe/redeem the fund
 * - Operators who manage day-to-day operations
 * - Admins who can handle operator tasks but also set economic parameters
 *
 * ## Operator Workflow
 * - Call {requestAdvanceEpoch} after each NAV report is published to update {_latestOffchainNAV}
 * - Call {requestRedemptionQueue} after assets have been deposited back into the vault to process queued redemptions
 * - Call {transferToTreasury} after deposits to move offchain
 */
contract FundVault is
    ERC4626Upgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    ChainlinkAccessor,
    AdminOperatorRoles,
    ERC1404,
    IFundVault
{
    using MathUpgradeable for uint256;
    using BytesQueue for BytesQueue.BytesDeque;

    BytesQueue.BytesDeque _redemptionQueue;
    uint256 public _latestOffchainNAV;

    uint256 private constant BPS_UNIT = 10000;

    uint256 public _minTxFee;
    uint256 public _onchainFee;
    uint256 public _offchainFee;
    uint256 public _epoch;

    address public _feeReceiver;
    address public _treasury;

    IBaseVault public _baseVault;
    IKycManager public _kycManager;

    mapping(address => bool) public _initialDeposit;
    mapping(address => mapping(uint256 => uint256)) _depositAmount; // account => [epoch => amount]
    mapping(address => mapping(uint256 => uint256)) _withdrawAmount; // account => [epoch => amount]

    ////////////////////////////////////////////////////////////
    // Init
    ////////////////////////////////////////////////////////////

    function initialize(
        IERC20Upgradeable asset,
        address operator,
        address feeReceiver,
        address treasury,
        IBaseVault baseVault,
        IKycManager kycManager,
        address chainlinkToken,
        address chainlinkOracle,
        ChainlinkParameters memory chainlinkParams
    ) external initializer {
        __ERC4626_init(asset);
        __ERC20_init("Cogito SFUND", "SFUND");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, operator);

        _feeReceiver = feeReceiver;
        _treasury = treasury;
        _baseVault = baseVault;
        _kycManager = kycManager;

        super.init(chainlinkParams, chainlinkToken, chainlinkOracle);
        _setMinTxFee(25 * 10 ** decimals()); // 25USDC
    }

    ////////////////////////////////////////////////////////////
    // Admin functions: Setting addresses
    ////////////////////////////////////////////////////////////

    function setFeeReceiver(address feeReceiver) external onlyAdmin {
        _feeReceiver = feeReceiver;
        emit SetFeeReceiver(feeReceiver);
    }

    function setTreasury(address newAddress) external onlyAdmin {
        _treasury = newAddress;
        emit SetTreasury(newAddress);
    }

    function setBaseVault(address baseVault) external onlyAdmin {
        _baseVault = IBaseVault(baseVault);
        emit SetBaseVault(baseVault);
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
     * Call after each NAV update has been published, in order to update {_latestOffchainNAV}.
     * @notice Do not call more than once per day, since {_getServiceFee} calculates daily fees.
     * @dev Handled in {_advanceEpoch}
     */
    function requestAdvanceEpoch() external onlyAdminOrOperator {
        bytes32 requestId = super._requestTotalOffchainNAV(_msgSender(), 0, Action.ADVANCE_EPOCH, decimals());

        emit RequestAdvanceEpoch(msg.sender, requestId);
    }

    /**
     * Call after sufficient assets have been returned to the vault to process redemptions.
     * @dev Handled in {_processRedemptionQueue}
     */
    function requestRedemptionQueue() external onlyAdminOrOperator {
        if (_redemptionQueue.empty()) {
            revert RedemptionQueueEmpty();
        }

        bytes32 requestId = super._requestTotalOffchainNAV(_msgSender(), 0, Action.REDEMPTION_QUEUE, decimals());

        emit RequestRedemptionQueue(msg.sender, requestId);
    }

    /**
     * Sweeps all asset to {_treasury}, keeping only the `targetReservesLevel` of assets
     */
    function transferExcessReservesToTreasury() external onlyAdminOrOperator {
        uint256 amount = excessReserves();
        if (amount == 0) {
            revert NoExcessReserves();
        }

        transferToTreasury(asset(), amount);
    }

    /**
     * Transfers any underlying assets to {_treasury}.
     */
    function transferToTreasury(address underlying, uint256 amount) public onlyAdminOrOperator {
        if (_treasury == address(0)) {
            revert InvalidAddress(_treasury);
        }

        if (underlying == asset() && amount > vaultNetAssets()) {
            revert InsufficientBalance(vaultNetAssets(), amount);
        }

        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(underlying), _treasury, amount);
        emit TransferToTreasury(_treasury, amount);
    }

    /**
     * Sets the minimum transaction fee
     */
    function setMinTxFee(uint256 newValue) external onlyAdminOrOperator {
        _setMinTxFee(newValue);
    }

    /**
     * Sends the accumulated onchain service fee to {_feeReceiver}
     */
    function claimOnchainServiceFee(uint256 amount) external onlyAdminOrOperator {
        if (_feeReceiver == address(0)) {
            revert InvalidAddress(_feeReceiver);
        }

        if (amount > _onchainFee) {
            amount = _onchainFee;
        }

        _onchainFee -= amount;
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), _feeReceiver, amount);
        emit ClaimOnchainServiceFee(msg.sender, _feeReceiver, amount);
    }

    /**
     * Sends the accumulated offchain service fee to {_feeReceiver}
     */
    function claimOffchainServiceFee(uint256 amount) external onlyAdminOrOperator {
        if (_feeReceiver == address(0)) {
            revert InvalidAddress(_feeReceiver);
        }

        if (amount > _offchainFee) {
            amount = _offchainFee;
        }

        _offchainFee -= amount;
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(asset()), _feeReceiver, amount);
        emit ClaimOffchainServiceFee(msg.sender, _feeReceiver, amount);
    }

    ////////////////////////////////////////////////////////////
    // Chainlink
    ////////////////////////////////////////////////////////////

    /**
     * Handler for Chainlink requests. Always contains the latest NAV data.
     * Processes deposits and redemptions, or updates epoch data
     */
    function fulfill(bytes32 requestId, uint256 latestOffchainNAV) external recordChainlinkFulfillment(requestId) {
        _latestOffchainNAV = latestOffchainNAV;

        (address investor, uint256 amount, Action action) = super.getRequestData(requestId);

        if (action == Action.DEPOSIT) {
            _processDeposit(investor, amount, requestId);
        } else if (action == Action.REDEEM) {
            _processRedemption(investor, amount, requestId);
        } else if (action == Action.REDEMPTION_QUEUE) {
            _processRedemptionQueue(requestId);
        } else if (action == Action.ADVANCE_EPOCH) {
            _advanceEpoch(requestId);
        }
        emit Fulfill(investor, requestId, latestOffchainNAV, amount, uint8(action));
    }

    ////////////////////////////////////////////////////////////
    // Public entrypoints
    ////////////////////////////////////////////////////////////

    /**
     * Subscribe to the fund.
     * @dev Handled in {_processDeposit}
     * @param assets Amount of {asset} to subscribe
     * @param receiver Must be msg.sender
     */
    function deposit(uint256 assets, address receiver)
        public
        override
        onlyCaller(receiver)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // receiver is msg.sender
        _kycManager.onlyKyc(receiver);
        _kycManager.onlyNotBanned(receiver);

        _validateDeposit(assets);
        bytes32 requestId = super._requestTotalOffchainNAV(receiver, assets, Action.DEPOSIT, decimals());

        emit RequestDeposit(receiver, assets, requestId);
        return 0;
    }

    /**
     * Redeem exact shares
     * @dev Handled in {_processRedemption}
     * @param shares Amount of shares to redeem
     * @param receiver Must be msg.sender
     * @param owner Must be msg.sender
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        override
        onlyCaller(receiver)
        onlyCaller(owner)
        nonReentrant
        whenNotPaused
        returns (uint256)
    {
        // receiver is msg.sender
        _kycManager.onlyKyc(receiver);
        _kycManager.onlyNotBanned(receiver);

        _validateRedemption(receiver, shares);
        bytes32 requestId = super._requestTotalOffchainNAV(receiver, shares, Action.REDEEM, decimals());

        emit RequestRedemption(receiver, shares, requestId);
        return 0;
    }

    /**
     * @notice Cannot be directly minted.
     */
    function mint(uint256, address) public pure override returns (uint256) {
        revert();
    }

    /**
     * @notice Asset balance may change between requesting and fulfilling, so using {withdraw} may result in
     * leftover assets. Use {redeem} instead.
     */
    function withdraw(uint256, address, address) public pure override returns (uint256) {
        revert();
    }

    ////////////////////////////////////////////////////////////
    // Public getters
    ////////////////////////////////////////////////////////////

    function getRedemptionQueueInfo(uint256 index) external view returns (address investor, uint256 shares) {
        if (_redemptionQueue.empty() || index > _redemptionQueue.length() - 1) {
            return (address(0), 0);
        }

        bytes memory data = bytes(_redemptionQueue.at(index));
        (investor, shares) = abi.decode(data, (address, uint256));
    }

    function getRedemptionQueueLength() external view returns (uint256) {
        return _redemptionQueue.length();
    }

    /**
     * Returns the maximum of the calculated fee and the minimum fee.
     */
    function getTxFee(uint256 assets) public view returns (uint256) {
        return _minTxFee.max((assets * _baseVault.getTransactionFee()) / BPS_UNIT);
    }

    // TODO: What are these used for?
    function previewDepositCustomize(uint256 assets, uint256 totalOffchainAsset) public view returns (uint256) {
        // based on _convertToShares
        uint256 supply = totalSupply();
        MathUpgradeable.Rounding rounding = MathUpgradeable.Rounding.Down;

        return (assets == 0 || supply == 0)
            ? _initialConvertToShares(assets, rounding)
            : assets.mulDiv(supply, totalOffchainAsset + vaultNetAssets(), rounding);
    }

    function previewRedeemCustomize(uint256 shares, uint256 totalOffchainAsset) public view returns (uint256) {
        // based on _convertToAssets
        uint256 supply = totalSupply();
        MathUpgradeable.Rounding rounding = MathUpgradeable.Rounding.Down;
        return (supply == 0)
            ? _initialConvertToAssets(shares, rounding)
            : shares.mulDiv(totalOffchainAsset + vaultNetAssets(), supply, rounding);
    }

    /**
     * Returns the requested deposit/withdraw amount for the given user for the current epoch, and the net amount
     */
    function getUserEpochInfo(address user, uint256 epoch)
        public
        view
        returns (uint256 depositAmt, uint256 withdrawAmt, uint256 delta)
    {
        depositAmt = _depositAmount[user][epoch];
        withdrawAmt = _withdrawAmount[user][epoch];

        delta = depositAmt >= withdrawAmt ? depositAmt - withdrawAmt : withdrawAmt - depositAmt;

        return (depositAmt, withdrawAmt, delta);
    }

    /**
     * @notice totalAssets(): returns the amount of vault assets (eg. USDC), including fees
     *
     * vaultNetAssets(): Returns vault assets, net fees
     */
    function vaultNetAssets() public view returns (uint256 amount) {
        return uint256(0).max(totalAssets() - _onchainFee - _offchainFee);
    }

    /**
     * combinedNetAssets(): Returns vault + offchain assets, net fees
     */
    function combinedNetAssets() public view returns (uint256 amount) {
        return _latestOffchainNAV + vaultNetAssets();
    }

    /**
     * excessReserves(): Returns the amount of assets in vault above the target reserve level, or 0 if below
     */
    function excessReserves() public view returns (uint256 amount) {
        uint256 targetReserves = _baseVault.getTargetReservesLevel() * combinedNetAssets() / 100;
        uint256 currentReserves = vaultNetAssets();
        return currentReserves - targetReserves.max(0);
    }

    ////////////////////////////////////////////////////////////
    // ERC-1404 Overrides
    ////////////////////////////////////////////////////////////

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
    // ERC-4626 Overrides
    ////////////////////////////////////////////////////////////

    function _convertToAssets(uint256 shares, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 assets)
    {
        uint256 supply = totalSupply();
        return (supply == 0)
            ? _initialConvertToAssets(shares, rounding)
            : shares.mulDiv(combinedNetAssets(), supply, rounding);
    }

    /**
     * @dev Internal conversion function (from shares to assets) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToShares} when overriding it.
     */
    function _initialConvertToAssets(uint256 shares, MathUpgradeable.Rounding /*rounding*/ )
        internal
        view
        virtual
        returns (uint256 assets)
    {
        return shares;
    }

    function _convertToShares(uint256 assets, MathUpgradeable.Rounding rounding)
        internal
        view
        override
        returns (uint256 shares)
    {
        uint256 supply = totalSupply();

        return (assets == 0 || supply == 0)
            ? _initialConvertToShares(assets, rounding)
            : assets.mulDiv(supply, combinedNetAssets(), rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) to apply when the vault is empty.
     *
     * NOTE: Make sure to keep this function consistent with {_initialConvertToAssets} when overriding it.
     */
    function _initialConvertToShares(uint256 assets, MathUpgradeable.Rounding /*rounding*/ )
        internal
        view
        virtual
        returns (uint256 shares)
    {
        return assets;
    }

    ////////////////////////////////////////////////////////////
    // Internal
    ////////////////////////////////////////////////////////////

    /**
     * Ensures deposit amount is within limits
     */
    function _validateDeposit(uint256 assets) internal view {
        // gas saving by defining local variable
        address sender = _msgSender();

        (uint256 minDeposit, uint256 maxDeposit) = _baseVault.getMinMaxDeposit();
        uint256 initialDeposit = _baseVault.getInitialDeposit();

        if (assets > _getAssetBalance(sender)) {
            revert InsufficientBalance(_getAssetBalance(sender), assets);
        }
        if (assets < minDeposit) {
            revert MinimumDepositRequired(minDeposit);
        }
        if (!_initialDeposit[sender] && assets < initialDeposit) {
            revert MinimumInitialDepositRequired(initialDeposit);
        }
        if (IERC20Upgradeable(asset()).allowance(sender, address(this)) < assets) {
            revert InsufficientAllowance(IERC20Upgradeable(asset()).allowance(sender, address(this)), assets);
        }

        (uint256 depositAmt, uint256 withdrawAmt, uint256 delta) = getUserEpochInfo(sender, _epoch);

        if (depositAmt >= withdrawAmt) {
            // Net deposit
            if (assets > maxDeposit - delta) {
                revert MaximumDepositExceeded(maxDeposit);
            }
        } else {
            // Net withdraw
            if (assets > maxDeposit + delta) {
                revert MaximumDepositExceeded(maxDeposit);
            }
        }
    }

    /**
     * Transfers assets from investor to vault, and tx fees to {_feeReceiver}
     */
    function _processDeposit(address investor, uint256 assets, bytes32 requestId) internal {
        uint256 txFee = getTxFee(assets);
        uint256 actualAsset = assets - txFee;

        uint256 shares = previewDeposit(actualAsset);
        super._deposit(investor, investor, actualAsset, shares);

        SafeERC20Upgradeable.safeTransferFrom(IERC20Upgradeable(asset()), investor, _feeReceiver, txFee);
        if (!_initialDeposit[investor]) {
            _initialDeposit[investor] = true;
        }

        _depositAmount[investor][_epoch] += actualAsset;
        emit ProcessDeposit(investor, assets, shares, requestId, txFee, _feeReceiver);
    }

    /**
     * Ensures withdraw amount is within limits
     */
    function _validateRedemption(address sender, uint256 share) internal view virtual {
        if (share > balanceOf(sender)) {
            revert InsufficientBalance(balanceOf(sender), share);
        }
        if (share == 0) {
            revert InvalidAmount(share);
        }

        (uint256 minWithdraw, uint256 maxWithdraw) = _baseVault.getMinMaxWithdraw();
        uint256 assets = previewRedeem(share);
        if (assets < minWithdraw) {
            revert MinimumWithdrawRequired(minWithdraw);
        }

        (uint256 depositAmt, uint256 withdrawAmt, uint256 delta) = getUserEpochInfo(sender, _epoch);

        if (depositAmt >= withdrawAmt) {
            // Net deposit
            if (assets > maxWithdraw + delta) {
                revert MaximumWithdrawExceeded(maxWithdraw);
            }
        } else {
            // Net withdraw
            if (assets > maxWithdraw - delta) {
                revert MaximumWithdrawExceeded(maxWithdraw);
            }
        }
    }

    /**
     * Burns shares and transfers assets to investor.
     * NOTE: If insufficient asset liquidity, then queue for later
     */
    function _processRedemption(address investor, uint256 requestedShares, bytes32 requestId) internal {
        if (requestedShares > balanceOf(investor)) {
            revert InsufficientBalance(balanceOf(investor), requestedShares);
        }
        uint256 availableAssets = vaultNetAssets();
        uint256 requestedAssets = previewRedeem(requestedShares);

        uint256 actualShares = requestedShares;
        uint256 actualAssets = requestedAssets;

        // Requested assets are insufficient, use all available
        if (actualAssets > availableAssets) {
            actualAssets = availableAssets;
            actualShares = previewWithdraw(actualAssets);
        }

        // Burn shares and transfer assets
        if (actualAssets > 0) {
            super._withdraw(investor, investor, investor, actualAssets, actualShares);
        }

        // Queue remaining shares for later
        if (requestedShares > actualShares) {
            uint256 remainingShares = requestedShares - actualShares;
            _redemptionQueue.pushBack(abi.encode(investor, remainingShares, requestId));
            super._transfer(investor, address(this), remainingShares);
            emit AddToRedemptionQueue(investor, remainingShares, requestId);
        }

        _withdrawAmount[investor][_epoch] += requestedAssets;
        emit ProcessRedemption(
            investor, requestedAssets, requestedShares, requestId, availableAssets, actualAssets, actualShares
        );
    }

    /**
     * Processes queued redemptions until no assets are remaining.
     * @dev May have remainders
     */
    function _processRedemptionQueue(bytes32 requestId) internal {
        for (; !_redemptionQueue.empty();) {
            bytes memory data = _redemptionQueue.front();
            (address investor, uint256 shares, bytes32 prevId) = abi.decode(data, (address, uint256, bytes32));

            uint256 assets = previewRedeem(shares);

            // we allow users to drain this vault by design
            if (assets > vaultNetAssets()) {
                return;
            }

            _redemptionQueue.popFront();
            super._withdraw(address(this), investor, address(this), assets, shares);

            emit ProcessRedemptionQueue(investor, assets, shares, requestId, prevId);
        }
    }

    /**
     * Advances epoch and accrues fees based on {BaseVault-getOnchainAndOffChainServiceFeeRate}
     */
    function _advanceEpoch(bytes32 requestId) internal {
        _epoch++;

        (uint256 onchainFeeRate, uint256 offchainFeeRate) = _baseVault.getOnchainAndOffChainServiceFeeRate();

        _onchainFee += _getServiceFee(vaultNetAssets(), onchainFeeRate);
        _offchainFee += _getServiceFee(_latestOffchainNAV, offchainFeeRate);

        emit ProcessAdvanceEpoch(_onchainFee, _offchainFee, _epoch, requestId);
    }

    function _setMinTxFee(uint256 newValue) internal {
        _minTxFee = newValue;
        emit SetMinTxFee(newValue);
    }

    function _getAssetBalance(address addr) internal view returns (uint256) {
        return IERC20Upgradeable(asset()).balanceOf(addr);
    }

    function _getServiceFee(uint256 assets, uint256 rate) internal pure returns (uint256 fee) {
        return (assets * rate) / (365 * BPS_UNIT);
    }

    ////////////////////////////////////////////////////////////
    // Needed since we inherit both Context and ContextUpgradeable
    ////////////////////////////////////////////////////////////

    function _msgSender() internal view virtual override(Context, ContextUpgradeable) returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual override(Context, ContextUpgradeable) returns (bytes calldata) {
        return msg.data;
    }
}
