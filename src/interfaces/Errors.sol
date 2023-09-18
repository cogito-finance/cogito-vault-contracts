// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @dev ERC-1066 codes
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1066.md
 */

uint8 constant SUCCESS_CODE = 0x01;
uint8 constant DISALLOWED_OR_STOP_CODE = 0x10;
uint8 constant REVOKED_OR_BANNED_CODE = 0x16;
string constant SUCCESS_MESSAGE = "Success";
string constant DISALLOWED_OR_STOP_MESSAGE = "User is not KYCed";
string constant REVOKED_OR_BANNED_MESSAGE = "User is banned";

error PermissionDenied();
error InvalidAddress(address addr);
error InvalidAmount(uint256 amount);
error UserMissingKyc(address user);
error UserBanned(address user);
error RedemptionQueueEmpty();
error NoExcessReserves();
error InsufficientBalance(uint256 current, uint256 needed);
error InsufficientAllowance(uint256 current, uint256 needed);
error MinimumDepositRequired(uint256 minimum);
error MinimumInitialDepositRequired(uint256 minimum);
error MaximumDepositExceeded(uint256 maximum);
error MinimumWithdrawRequired(uint256 minimum);
error MaximumWithdrawExceeded(uint256 maximum);
