// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/access/Ownable.sol";

import "./interfaces/Action.sol";
import "./interfaces/IBaseVault.sol";

/**
 * Stores parameters that are used by all vaults.
 */
contract BaseVault is Ownable, IBaseVault {
    uint256 _transactionFee; // in bps
    uint256 _initialDeposit;
    uint256 _minDeposit;
    uint256 _maxDeposit;
    uint256 _minWithdraw;
    uint256 _maxWithdraw;
    uint256 _targetReservesLevel; // in percent
    uint256 _onchainServiceFeeRate; // in bps
    uint256 _offchainServiceFeeRate; // in bps

    constructor(
        uint256 transactionFee,
        uint256 initialDeposit,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 minWithdraw,
        uint256 maxWithdraw,
        uint256 targetReservesLevel,
        uint256 onchainServiceFeeRate,
        uint256 offchainServiceFeeRate
    ) {
        _transactionFee = transactionFee;
        _initialDeposit = initialDeposit;
        _minDeposit = minDeposit;
        _maxDeposit = maxDeposit;
        _minWithdraw = minWithdraw;
        _maxWithdraw = maxWithdraw;
        _targetReservesLevel = targetReservesLevel;
        _onchainServiceFeeRate = onchainServiceFeeRate;
        _offchainServiceFeeRate = offchainServiceFeeRate;
    }

    ////////////////////////////////////////////////////////////
    // Owner setters
    ////////////////////////////////////////////////////////////

    function setTransactionFee(uint256 transactionFee) external onlyOwner {
        _transactionFee = transactionFee;
        emit SetTransactionFee(transactionFee);
    }

    function setInitialDeposit(uint256 initialDeposit) external onlyOwner {
        _initialDeposit = initialDeposit;
        emit SetInitialDeposit(initialDeposit);
    }

    function setMinDeposit(uint256 minDeposit) external onlyOwner {
        _minDeposit = minDeposit;
        emit SetMinDeposit(minDeposit);
    }

    function setMaxDeposit(uint256 maxDeposit) external onlyOwner {
        _maxDeposit = maxDeposit;
        emit SetMaxDeposit(maxDeposit);
    }

    function setMinWithdraw(uint256 minWithdraw) external onlyOwner {
        _minWithdraw = minWithdraw;
        emit SetMinWithdraw(minWithdraw);
    }

    function setMaxWithdraw(uint256 maxWithdraw) external onlyOwner {
        _maxWithdraw = maxWithdraw;
        emit SetMaxWithdraw(maxWithdraw);
    }

    function setTargetReservesLevel(uint256 targetReservesLevel) external onlyOwner {
        _targetReservesLevel = targetReservesLevel;
        emit SetTargetReservesLevel(targetReservesLevel);
    }

    function setOnchainServiceFeeRate(uint256 onchainServiceFeeRate) external onlyOwner {
        _onchainServiceFeeRate = onchainServiceFeeRate;
        emit SetOnchainServiceFeeRate(onchainServiceFeeRate);
    }

    function setOffchainServiceFeeRate(uint256 offchainServiceFeeRate) external onlyOwner {
        _offchainServiceFeeRate = offchainServiceFeeRate;
        emit SetOffchainServiceFeeRate(offchainServiceFeeRate);
    }

    ////////////////////////////////////////////////////////////
    // Public getters
    ////////////////////////////////////////////////////////////

    function getTransactionFee() external view returns (uint256 txFee) {
        return _transactionFee;
    }

    function getMinMaxDeposit() external view returns (uint256 minDeposit, uint256 maxDeposit) {
        return (_minDeposit, _maxDeposit);
    }

    function getMinMaxWithdraw() external view returns (uint256 minWithdraw, uint256 maxWithdraw) {
        return (_minWithdraw, _maxWithdraw);
    }

    function getTargetReservesLevel() external view returns (uint256 targetReservesLevel) {
        return _targetReservesLevel;
    }

    function getOnchainAndOffChainServiceFeeRate()
        external
        view
        returns (uint256 onchainFeeRate, uint256 offchainFeeRate)
    {
        return (_onchainServiceFeeRate, _offchainServiceFeeRate);
    }

    function getInitialDeposit() external view returns (uint256 initialDeposit) {
        return _initialDeposit;
    }
}
