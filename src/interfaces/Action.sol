// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

enum Action {
    DEPOSIT,
    WITHDRAW,
    ADVANCE_EPOCH,
    WITHDRAW_QUEUE
}

struct VaultParameters {
    uint256 transactionFee;
    uint256 initialDeposit;
    uint256 minDeposit;
    uint256 maxDeposit;
    uint256 maxWithdraw;
    uint256 targetReservesLevel;
    uint256 onchainServiceFeeRate;
    uint256 offchainServiceFeeRate;
}
