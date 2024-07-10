// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "chainlink/mocks/MockLinkToken.sol";
import "forge-std/Test.sol";

import "../../src/KycManager.sol";
import "../../src/interfaces/Errors.sol";
import "../../src/utils/ERC1404.sol";
import "../../src/v1/BaseVault.sol";
import "../../src/v1/FundVault.sol";
import "../../src/v1/interfaces/IFundVaultEvents.sol";
import "./helpers/FundVaultFactory.sol";
import "../../src/mocks/USDC.sol";

contract ForkTest is Test, IFundVaultEvents {
    address public constant deployer = address(0x941C167E087F3a23E456e26908827eCB80E2dd93);
    address public constant tester = address(0x9BD8dFF7D3b18d51d40C0dCe0048a95854a5d758);
    address public constant fundVaultAddress = address(0x94890046239198a976935B0D3db7453246D83C4d);
    address public constant oracle = address(0x1db329cDE457D68B872766F4e12F9532BCA9149b);

    FundVault fundVault = FundVault(fundVaultAddress);

    function getRequestId() public view returns (bytes32) {
        return keccak256(abi.encodePacked(fundVault, uint256(6)));
    }

    constructor() {
        string memory MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");
        uint256 forkId = vm.createFork(MAINNET_RPC_URL, 20225823);
        vm.selectFork(forkId);

        vm.label(deployer, "deployer");
        vm.label(tester, "tester");
        vm.label(fundVaultAddress, "FundVault");
        vm.label(oracle, "oracle");

        uint256 totalSupply = fundVault.totalSupply();
        console.log("starting TFUND: %s (%s)", totalSupply, totalSupply / 1e6);

        uint256 totalAssets = fundVault.totalAssets();
        console.log("starting USDC: %s (%s)", totalAssets, totalAssets / 1e6);

        uint256 combinedNetAssets = fundVault.combinedNetAssets();
        console.log("starting NAV: %s (%s)", combinedNetAssets, combinedNetAssets / 1e6);
        console.log("----------");

        uint256 inputAmount = (400_000e6);
        uint256 newSupply = fundVault.previewDeposit(inputAmount);
        uint256 netSupply = totalSupply + newSupply;

        console.log("actual USDC deposit: %s (%s)", inputAmount, inputAmount / 1e6);
        console.log("actual minted TFUND: %s (%s)", newSupply, newSupply / 1e6);
        console.log("actual ending TFUND: %s (%s)", netSupply, netSupply / 1e6);
        console.log("----------");
        // console.log("price per TFUND: %e", inputAmount * 1e8 / newSupply);

        uint256 newOffchainNav = 102515850000;
        console.log("correct set offchain NAV: %s (%s)", newOffchainNav, newOffchainNav / 1e6);

        vm.expectEmit();
        emit RequestAdvanceEpoch(deployer, getRequestId());
        vm.prank(deployer);
        fundVault.requestAdvanceEpoch();
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), newOffchainNav);

        uint256 correctNewSupply = fundVault.previewDeposit(inputAmount);
        uint256 correctNetSupply = totalSupply + correctNewSupply;
        console.log("correct USDC deposit: %s (%s)", inputAmount, inputAmount / 1e6);
        console.log("correct minted TFUND: %s (%s)", correctNewSupply, correctNewSupply / 1e6);
        console.log("correct ending TFUND: %s (%s)", correctNetSupply, correctNetSupply / 1e6);
    }
}
