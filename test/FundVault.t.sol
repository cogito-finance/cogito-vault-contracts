// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "chainlink/mocks/MockLinkToken.sol";
import "forge-std/Test.sol";

import "../src/BaseVault.sol";
import "../src/KycManager.sol";
import "../src/FundVault.sol";
import "../src/interfaces/IFundVaultEvents.sol";
import "../src/interfaces/IKycManager.sol";
import "./mock/IChainlinkClient.sol";
import "./mock/USDC.sol";

contract VaultTest is Test, IFundVaultEvents, IChainlinkClient {
    USDC public usdc;
    MockLinkToken public link;
    BaseVault public baseVault;
    KycManager public kycManager;
    FundVault public fundVault;

    address constant alice = address(0xdeadbeef1);
    address constant bob = address(0xdeadbeef2);
    address constant charlie = address(0xdeadbeef3);

    uint256 private nonce = 1;

    // Set up the testing environment before each test
    function setUp() public {
        // Deploy USDC and LINK
        usdc = new USDC();
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        link = new MockLinkToken();

        baseVault = new BaseVault(
            5,                  // transactionFee
            100000000000,       // initialDeposit
            10000000000,        // minDeposit
            1000000000000000,   // maxDeposit
            10000000000,        // minWithdraw
            1000000000000000,   // maxWithdraw
            10,                 // targetReservesLevel
            10,                 // onchainServiceFeeRate
            50                  // offchainServiceFeeRate
        );

        // Approve alice & bob
        kycManager = new KycManager();
        address[] memory _investors = new address[](2);
        _investors[0] = alice;
        _investors[1] = bob;
        IKycManager.KycType[] memory _kycTypes = new IKycManager.KycType[](2);
        _kycTypes[0] = IKycManager.KycType.GENERAL_KYC;
        _kycTypes[1] = IKycManager.KycType.GENERAL_KYC;
        kycManager.grantKycInBulk(_investors, _kycTypes);

        IChainlinkAccessor.ChainlinkParameters memory chainlinkParams = IChainlinkAccessor.ChainlinkParameters({
            jobId: vm.envBytes32("CHAINLINK_JOBID"),
            fee: vm.envUint("CHAINLINK_FEE"),
            urlData: vm.envString("CHAINLINK_URL_DATA"),
            pathToOffchainAssets: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS"),
            pathToTotalOffchainAssetAtLastClose: vm.envString("CHAINLINK_PATH_TO_OFFCHAIN_ASSETS_AT_LAST_CLOSE")
        });

        fundVault = new FundVault();
        fundVault.initialize(
            IERC20Upgradeable(address(usdc)),
            vm.envAddress("OPERATOR_ADDRESS"),
            vm.envAddress("FEE_RECEIVER_ADDRESS"),
            vm.envAddress("TREASURY_ADDRESS"),
            baseVault,
            kycManager,
            address(link),
            vm.envAddress("CHAINLINK_ORACLE_ADDRESS"),
            chainlinkParams
        );
        link.transfer(address(fundVault), 10);
    }

    function getRequestId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(fundVault, uint256(nonce++)));
    }

    function test_Deposit_NoKyc() public {
        vm.expectRevert("user has no kyc");
        vm.prank(charlie);
        fundVault.deposit(100_000e6, charlie);
    }

    function test_Deposit_NoMinimum() public {
        vm.startPrank(alice);
        vm.expectRevert("amount < minimum deposit");
        fundVault.deposit(100e6, alice);

        vm.expectRevert("amount < minimum initial deposit");
        fundVault.deposit(10_000e6, alice);
        vm.stopPrank();
    }

    function test_Deposit_Ok() public {
        bytes32 requestId = getRequestId();
        vm.prank(alice);

        vm.expectEmit();
        emit ChainlinkRequested(requestId);

        vm.expectEmit();
        emit RequestDeposit(alice, 100_000e6, requestId);
        assertEq(fundVault.deposit(100_000e6, alice), 0);
    }
}
