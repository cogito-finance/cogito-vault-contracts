// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "chainlink/mocks/MockLinkToken.sol";
import "forge-std/Test.sol";

import "../../src/BaseVault.sol";
import "../../src/KycManager.sol";
import "../../src/utils/ERC1404.sol";
import "../../src/FundVault.sol";
import "../../src/interfaces/IFundVaultEvents.sol";
import "../../src/interfaces/Errors.sol";
import "../../src/mocks/USDC.sol";
import "./ITestEvents.sol";

contract FundVaultFactory is Test, IFundVaultEvents, ITestEvents {
    USDC public usdc;
    MockLinkToken public link;
    BaseVault public baseVault;
    KycManager public kycManager;
    FundVault public fundVault;

    address public constant alice = address(0xdeadbeef1);
    address public constant bob = address(0xdeadbeef2);
    address public constant charlie = address(0xdeadbeef3);
    address public constant dprk = address(0xdeadbeef4);
    address public constant oracle = address(0xcafecafe1);
    address public constant operator = address(0xcafecafe2);
    address public constant treasury = address(0xcafecafe3);
    address public constant feeReceiver = address(0xcafecafe4);

    uint256 private nonce = 0;

    // Set up the testing environment before each test
    constructor() {
        // Deploy USDC and LINK
        usdc = new USDC();
        link = new MockLinkToken();

        baseVault = new BaseVault(
            5,                  // transactionFee: 5bps
            100000000000,       // initialDeposit: 100,000
            10000000000,        // minDeposit: 10,000
            1000000000000000,   // maxDeposit: 1B
            10000000000,        // minWithdraw: 10,000
            1000000000000000,   // maxWithdraw: 1B
            5,                  // targetReservesLevel: 5%
            10,                 // onchainServiceFeeRate: 10bps
            50                  // offchainServiceFeeRate: 50bps
        );

        // Approve alice & bob
        kycManager = new KycManager(true);
        address[] memory _investors = new address[](2);
        _investors[0] = alice;
        _investors[1] = bob;
        IKycManager.KycType[] memory _kycTypes = new IKycManager.KycType[](2);
        _kycTypes[0] = IKycManager.KycType.GENERAL_KYC;
        _kycTypes[1] = IKycManager.KycType.GENERAL_KYC;
        kycManager.bulkGrantKyc(_investors, _kycTypes);
        address[] memory _banned = new address[](1);
        _banned[0] = dprk;
        kycManager.bulkBan(_banned);

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
        link.transfer(address(fundVault), 100e18);

        usdc.mint(alice, 100_000e6);

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

    function getRequestId() public view returns (bytes32) {
        return keccak256(abi.encodePacked(fundVault, uint256(nonce)));
    }

    function nextRequestId() public {
        nonce++;
    }

    function alice_deposit(uint256 amount) public {
        make_deposit(alice, amount);
    }

    function make_deposit(address user, uint256 amount) public {
        // Deposit.1
        nextRequestId();
        vm.startPrank(user);
        usdc.approve(address(fundVault), amount);
        fundVault.deposit(amount, user);
        vm.stopPrank();

        // Deposit.2
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), 0);
    }
}
