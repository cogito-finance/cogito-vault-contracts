// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "openzeppelin-contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "openzeppelin-contracts/proxy/transparent/ProxyAdmin.sol";
import "forge-std/Test.sol";

import "../../../src/KycManager.sol";
import "../../../src/utils/ERC1404.sol";
import "../../../src/interfaces/Errors.sol";
import "../../../src/v2/FundVaultV2Upgradeable.sol";
import "../../../src/v2/interfaces/IFundVaultEventsV2.sol";
import "../../../src/mocks/USDC.sol";
import "./ITestEvents.sol";

contract FundVaultFactoryV2 is Test, IFundVaultEventsV2, ITestEvents {
    USDC public usdc;
    KycManager public kycManager;
    FundVaultV2Upgradeable public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    FundVaultV2Upgradeable public fundVault;

    address public constant alice = address(0xdeadbeef1);
    address public constant bob = address(0xdeadbeef2);
    address public constant charlie = address(0xdeadbeef3);
    address public constant dprk = address(0xdeadbeef4);
    address public constant oracle = address(0xcafecafe1);
    address public constant operator = address(0xcafecafe2);
    address public constant custodian = address(0xcafecafe3);
    address public constant feeReceiver = address(0xcafecafe4);

    uint256 private nonce = 0;

    // Set up the testing environment before each test
    constructor() {
        // Deploy USDC
        usdc = new USDC();

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

        // Deploy proxy admin
        proxyAdmin = new ProxyAdmin();

        // Deploy implementation
        implementation = new FundVaultV2Upgradeable();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            FundVaultV2Upgradeable.initialize.selector,
            operator,
            custodian,
            kycManager
        );

        // Deploy proxy
        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // Create interface to proxy
        fundVault = FundVaultV2Upgradeable(address(proxy));

        usdc.mint(alice, 100_000e6);

        // Add labels
        vm.label(alice, "alice");
        vm.label(bob, "bob");
        vm.label(charlie, "charlie");
        vm.label(oracle, "oracle");
        vm.label(operator, "operator");
        vm.label(custodian, "custodian");
        vm.label(address(usdc), "USDC");
        vm.label(address(proxy), "FundVault Proxy");
        vm.label(address(implementation), "FundVault Implementation");
        vm.label(address(proxyAdmin), "Proxy Admin");
    }

    function alice_deposit(uint256 amount) public {
        make_deposit(alice, amount);
    }

    function make_deposit(address user, uint256 amount) public {
        vm.startPrank(user);
        usdc.approve(address(fundVault), amount);
        fundVault.deposit(address(usdc), amount);
        vm.stopPrank();

        vm.startPrank(operator);
        fundVault.processDeposit(user, address(usdc), amount, amount);
        fundVault.setFundNav(amount);
        vm.stopPrank();
    }

    // Helper function to upgrade the contract
    function upgradeToNewImplementation(address newImplementation) public {
        vm.prank(address(this));
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(proxy)),
            newImplementation,
            ""
        );
    }

    // Helper function to check if proxy is pointing to correct implementation
    function getImplementation() public view returns (address) {
        return proxyAdmin.getProxyImplementation(ITransparentUpgradeableProxy(address(proxy)));
    }
}