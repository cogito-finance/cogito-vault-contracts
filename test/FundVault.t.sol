// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "chainlink/mocks/MockLinkToken.sol";
import "forge-std/Test.sol";

import "../src/BaseVault.sol";
import "../src/KycManager.sol";
import "../src/utils/ERC1404.sol";
import "../src/FundVault.sol";
import "../src/interfaces/IFundVaultEvents.sol";
import "../src/interfaces/Errors.sol";
import "./mock/ITestEvents.sol";
import "./mock/USDC.sol";

contract VaultTest is Test, IFundVaultEvents, ITestEvents {
    USDC public usdc;
    MockLinkToken public link;
    BaseVault public baseVault;
    KycManager public kycManager;
    FundVault public fundVault;

    address constant alice = address(0xdeadbeef1);
    address constant bob = address(0xdeadbeef2);
    address constant charlie = address(0xdeadbeef3);
    address constant dprk = address(0xdeadbeef4);
    address constant oracle = address(0xcafecafe1);
    address constant operator = address(0xcafecafe2);
    address constant treasury = address(0xcafecafe3);
    address constant feeReceiver = address(0xcafecafe4);

    uint256 private nonce = 1;

    // Set up the testing environment before each test
    function setUp() public {
        // Deploy USDC and LINK
        usdc = new USDC();
        link = new MockLinkToken();

        baseVault = new BaseVault(
            5,                  // transactionFee
            100000000000,       // initialDeposit
            10000000000,        // minDeposit
            1000000000000000,   // maxDeposit
            10000000000,        // minWithdraw
            1000000000000000,   // maxWithdraw
            5,                  // targetReservesLevel
            10,                 // onchainServiceFeeRate
            50                  // offchainServiceFeeRate
        );

        // Approve alice & bob
        kycManager = new KycManager(true);
        address[] memory _investors = new address[](2);
        _investors[0] = alice;
        _investors[1] = bob;
        IKycManager.KycType[] memory _kycTypes = new IKycManager.KycType[](2);
        _kycTypes[0] = IKycManager.KycType.GENERAL_KYC;
        _kycTypes[1] = IKycManager.KycType.GENERAL_KYC;
        kycManager.grantKycInBulk(_investors, _kycTypes);
        address[] memory _banned = new address[](1);
        _banned[0] = dprk;
        kycManager.bannedInBulk(_banned);

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
            operator,
            feeReceiver,
            treasury,
            baseVault,
            kycManager,
            address(link),
            oracle,
            chainlinkParams
        );
        link.transfer(address(fundVault), 10);

        usdc.mint(alice, 1_000_000e6);

        // Add labels
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
        vm.label(oracle, "oracle");
        vm.label(operator, "operator");
        vm.label(treasury, "treasury");
        vm.label(feeReceiver, "feeReceiver");
        vm.label(address(usdc), "USDC");
        vm.label(address(fundVault), "FundVault");
    }

    function getRequestId() internal returns (bytes32) {
        return keccak256(abi.encodePacked(fundVault, uint256(nonce++)));
    }

    function test_Fulfill_OnlyOracle() public {
        vm.expectRevert("Source must be the oracle of the request");
        vm.prank(alice);
        fundVault.fulfill(bytes32(0), 0);
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

    function test_Deposit_FulfillAndTransferOut() public {
        uint256 amount = 100_000e6;

        bytes32 requestId = getRequestId();
        vm.startPrank(alice);
        usdc.approve(address(fundVault), amount);

        vm.expectEmit();
        emit ChainlinkRequested(requestId);

        vm.expectEmit();
        emit RequestDeposit(alice, amount, requestId);
        assertEq(fundVault.deposit(amount, alice), 0);
        vm.stopPrank();

        vm.prank(oracle);
        fundVault.fulfill(requestId, 0);

        uint256 txFee = fundVault.getTxFee(amount);
        assertEq(usdc.balanceOf(address(fundVault)), amount - txFee);
        assertEq(usdc.balanceOf(feeReceiver), txFee);
        assertGt(fundVault.balanceOf(alice), 0);
        assertEq(fundVault.vaultNetAssets(), fundVault.totalAssets());
        uint256 targetReserves = 5 * (amount - txFee) / 100;
        uint256 expectedExcessReserves = fundVault.vaultNetAssets() - targetReserves;
        assertEq(fundVault.excessReserves(), expectedExcessReserves);

        vm.prank(operator);
        fundVault.transferExcessReservesToTreasury();

        assertEq(
            usdc.balanceOf(treasury), expectedExcessReserves, "treasury balance should be > expectedExcessReserves"
        );
        assertEq(fundVault.vaultNetAssets(), targetReserves, "vaultNetAssets should be targetReserves");

        // Transfer: no kyc
        vm.expectRevert(bytes(DISALLOWED_OR_STOP_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(charlie, 1);

        // Transfer: banned
        vm.expectRevert(bytes(REVOKED_OR_BANNED_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(dprk, 1);

        // Transfer: ok
        vm.expectEmit();
        emit Transfer(alice, bob, 1);
        vm.prank(alice);
        fundVault.transfer(bob, 1);
    }
}
