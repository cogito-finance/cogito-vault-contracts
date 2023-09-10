// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Action.sol";

interface IBaseVault {
    event SetTransactionFee(uint256 transactionFee);
    event SetFirsetDeposit(uint256 initialDeposit);
    event SetMinDeposit(uint256 minDeposit);
    event SetMaxDeposit(uint256 maxDeposit);
    event SetMinWithdraw(uint256 minWithdraw);
    event SetMaxWithdraw(uint256 maxWithdraw);
    event SetTargetReservesLevel(uint256 targetReservesLevel);
    event SetOnchainServiceFeeRate(uint256 onchainServiceFeeRate);
    event SetOffchainServiceFeeRate(uint256 offchainServiceFeeRate);
    event SetInitialDeposit(uint256 initialDeposit);

    function getTransactionFee() external view returns (uint256 txFee);

    function getMinMaxDeposit() external view returns (uint256 minDeposit, uint256 maxDeposit);

    function getMinMaxWithdraw() external view returns (uint256 minWithdraw, uint256 maxWithdraw);

    function getTargetReservesLevel() external view returns (uint256 targetReservesLevel);

    function getOnchainAndOffChainServiceFeeRate()
        external
        view
        returns (uint256 onchainFeeRate, uint256 offchainFeeRate);

    function getInitialDeposit() external view returns (uint256 initialDeposit);
}
