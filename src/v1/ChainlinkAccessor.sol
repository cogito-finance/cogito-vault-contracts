// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "chainlink/ChainlinkClient.sol";

import "./interfaces/IChainlinkAccessor.sol";
import "./interfaces/IFundVault.sol";
import "../utils/AdminRole.sol";

/**
 * Wrapper for ChainlinkClient. Builds Chainlink requests
 */
abstract contract ChainlinkAccessor is IChainlinkAccessor, ChainlinkClient, AdminRole {
    using Chainlink for Chainlink.Request;

    ChainlinkParameters _params;
    mapping(bytes32 => RequestData) internal _requestIdToRequestData; // requestId => RequestData

    /**
     * @dev Initializes Chainlink parameters, token, and oracle.
     * @param params Chainlink parameters containing fee, jobId, urlData, and paths.
     * @param chainlinkToken Address of the Chainlink token.
     * @param chainlinkOracle Address of the Chainlink oracle.
     */
    function init(ChainlinkParameters memory params, address chainlinkToken, address chainlinkOracle) internal {
        _params.fee = params.fee;
        _params.jobId = params.jobId;
        _params.urlData = params.urlData;
        _params.pathToOffchainAssets = params.pathToOffchainAssets;
        _params.pathToTotalOffchainAssetAtLastClose = params.pathToTotalOffchainAssetAtLastClose;
        setChainlinkOracle(chainlinkOracle);
        setChainlinkToken(chainlinkToken);
    }

    /**
     * Build and send request to offchain API for NAV data.
     */
    function _requestTotalOffchainNAV(address investor, uint256 amount, Action action, uint8 decimals)
        internal
        returns (bytes32 requestId)
    {
        Chainlink.Request memory req = buildChainlinkRequest(
            _params.jobId,
            // NOTE: this will be ignored and replace by address(this) during encode
            address(0),
            IFundVault(address(this)).fulfill.selector
        );

        // Set the URL to perform the GET request on
        req.add(
            "get",
            _params.urlData // offchain assets url
        );
        if (action == Action.ADVANCE_EPOCH) {
            req.add("path", _params.pathToTotalOffchainAssetAtLastClose);
        } else {
            req.add("path", _params.pathToOffchainAssets);
        }

        // Multiply the result by decimals
        int256 timesAmount = int256(10 ** decimals);
        req.addInt("times", timesAmount);
        RequestData memory requestData = RequestData(investor, amount, action);

        requestId = sendChainlinkRequest(req, _params.fee);

        // Add to mapping
        _requestIdToRequestData[requestId] = requestData;
    }

    function setChainlinkOracleAddress(address newAddress) external onlyAdmin {
        super.setChainlinkOracle(newAddress);
        emit SetChainlinkOracleAddress(newAddress);
    }

    function setChainlinkFee(uint256 fee) external onlyAdmin {
        _params.fee = fee;
        emit SetChainlinkFee(fee);
    }

    function setChainlinkJobId(bytes32 jobId) external onlyAdmin {
        _params.jobId = jobId;
        emit SetChainlinkJobId(jobId);
    }

    function setChainlinkURLData(string memory url) external onlyAdmin {
        _params.urlData = url;
        emit SetChainlinkURLData(url);
    }

    function setPathToOffchainAssets(string memory path) external onlyAdmin {
        _params.pathToOffchainAssets = path;
        emit SetPathToOffchainAssets(path);
    }

    function setPathToTotalOffchainAssetAtLastClose(string memory path) external onlyAdmin {
        _params.pathToTotalOffchainAssetAtLastClose = path;
        emit SetPathToTotalOffchainAssetAtLastClose(path);
    }

    function getChainLinkParameters() external view returns (ChainlinkParameters memory params) {
        params = _params;
    }

    function getRequestData(bytes32 requestId) public view returns (address investor, uint256 amount, Action action) {
        investor = _requestIdToRequestData[requestId].investor;
        amount = _requestIdToRequestData[requestId].amount;
        action = _requestIdToRequestData[requestId].action;
    }
}
