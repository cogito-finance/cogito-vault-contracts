// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IFundVaultEventsV2 {
    event SetCustodian(address newAddress);
    event SetKycManager(address kycManager);
    event SetFundNav(uint256 nav);

    event TransferToCustodian(address receiver, address asset, uint256 amount);

    event RequestDeposit(address investor, address asset, uint256 amount);
    event ProcessDeposit(address investor, address asset, uint256 amount);
    event RequestRedemption(address investor, uint256 shares, address asset);
    event ProcessRedemption(address investor, uint256 shares, address asset, uint256 amount);
}
