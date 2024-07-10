// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFundVaultEvents {
    event SetFeeReceiver(address feeReceiver);
    event SetTreasury(address newAddress);
    event SetBaseVault(address baseVault);
    event SetKycManager(address kycManager);
    event SetMinTxFee(uint256 newValue);

    event ClaimOnchainServiceFee(address caller, address receiver, uint256 amount);
    event ClaimOffchainServiceFee(address caller, address receiver, uint256 amount);
    event TransferToTreasury(address receiver, address asset, uint256 amount);

    event RequestAdvanceEpoch(address caller, bytes32 requestId);
    event ProcessAdvanceEpoch(
        uint256 onchainFeeClaimable, uint256 offchainFeeClaimable, uint256 epoch, bytes32 requestId
    );

    event AddToRedemptionQueue(address investor, uint256 shares, bytes32 requestId);
    event RequestRedemptionQueue(address caller, bytes32 requestId);
    event ProcessRedemptionQueue(address investor, uint256 assets, uint256 shares, bytes32 requestId, bytes32 prevId);

    event RequestDeposit(address receiver, uint256 assets, bytes32 requestId);
    event ProcessDeposit(
        address receiver, uint256 assets, uint256 shares, bytes32 requestId, uint256 txFee, address feeReceiver
    );
    event RequestRedemption(address receiver, uint256 shares, bytes32 requestId);
    event ProcessRedemption(
        address receiver,
        uint256 requestedAssets,
        uint256 requestedShares,
        bytes32 requestId,
        uint256 availableAssets,
        uint256 actualAssets,
        uint256 actualShares
    );

    event Fulfill(address investor, bytes32 requestId, uint256 _latestOffchainNAV, uint256 amount, uint8 action);
}
