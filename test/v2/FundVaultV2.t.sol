// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "openzeppelin-contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "chainlink/mocks/MockLinkToken.sol";
import "forge-std/Test.sol";

import "../../src/KycManager.sol";
import "../../src/interfaces/Errors.sol";
import "../../src/utils/ERC1404Upgradeable.sol";
import "../../src/v2/FundVaultV2Upgradeable.sol";
import "../../src/v2/interfaces/IFundVaultEventsV2.sol";
import "./helpers/FundVaultFactoryV2.sol";
import "../../src/mocks/USDC.sol";

contract VaultTestBasicV2 is FundVaultFactoryV2 {
    function test_Decimals() public {
        assertEq(fundVault.decimals(), 6);
    }

    function test_Admin_Permissions() public {
        fundVault.setCustodian(address(4));
        assertEq(fundVault._custodian(), address(4));

        fundVault.setKycManager(address(9));
        assertEq(address(fundVault._kycManager()), address(9));
    }

    function test_Operator_Permissions() public {
        bytes memory errorMsg = abi.encodePacked(
            "AccessControl: account ", Strings.toHexString(operator), " is missing role ", Strings.toHexString(0, 32)
        );
        vm.expectRevert(errorMsg);
        vm.prank(operator);
        fundVault.setCustodian(operator);

        vm.expectRevert(errorMsg);
        vm.prank(operator);
        fundVault.setKycManager(address(0));
    }

    function test_Deposit_RevertWhenNoKyc() public {
        vm.expectRevert(abi.encodeWithSelector(UserMissingKyc.selector, charlie));
        vm.prank(charlie);
        fundVault.deposit(address(usdc), 100_000e6);
    }

    function test_Deposit_RevertWhenPaused() public {
        vm.prank(operator);
        fundVault.pause();
        vm.expectRevert("Pausable: paused");
        vm.prank(alice);
        fundVault.deposit(address(usdc), 100_000e6);

        vm.prank(operator);
        fundVault.unpause();
        alice_deposit(100_000e6);
        assert(true);
    }

    function test_Deposit_RevertWhenNotEnoughBalance() public {
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 100_000e6, 200_000e6));
        vm.prank(alice);
        fundVault.deposit(address(usdc), 200_000e6);
    }

    function test_Deposit_RevertWhenNotEnoughAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(InsufficientAllowance.selector, 0, 100_000e6));
        vm.prank(alice);
        fundVault.deposit(address(usdc), 100_000e6);
    }

    function test_Mint_Permissions_Operator() public {
        vm.expectEmit();
        emit Transfer(address(0), alice, 12);
        vm.prank(operator);
        fundVault.mint(alice, 12);
    }

    function test_Mint_Permissions() public {
        vm.expectRevert();
        vm.prank(alice);
        fundVault.mint(alice, 100_000e6);
    }

    function test_Burn_Permissions_Operator() public {
        alice_deposit(100_000e6);

        vm.expectEmit();
        emit Transfer(alice, address(0), 500);
        vm.prank(operator);
        fundVault.burnFrom(alice, 500);
    }

    function test_Burn_Permissions() public {
        alice_deposit(100_000e6);
        vm.expectRevert();
        vm.prank(bob);
        fundVault.burnFrom(alice, 1);
    }

    function test_Withdraw_RevertWhenNoShares() public {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 0, 1));
        fundVault.redeem(1, address(usdc));
    }

    function test_TransferToCustodian_RevertWhenMoreThanAvailable() public {
        alice_deposit(100_000e6);
        // vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 99_950e6, 150_000e6));
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(operator);
        fundVault.transferToCustodian(address(usdc), 150_000e6);
    }
}

contract VaultTestTransferV2 is FundVaultFactoryV2 {
    function setUp() public {
        alice_deposit(100_000e6);
    }

    function test_Transfers() public {
        // no kyc
        vm.expectRevert(bytes(DISALLOWED_OR_STOP_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(charlie, 1);

        // banned
        vm.expectRevert(bytes(REVOKED_OR_BANNED_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(dprk, 1);

        // ok
        vm.expectEmit();
        emit Transfer(alice, bob, 1);
        vm.prank(alice);
        fundVault.transfer(bob, 1);

        // no sending to 0
        vm.expectRevert("ERC20: transfer to the zero address");
        vm.prank(alice);
        fundVault.transfer(address(0), 1);

        // sender kyc revoked
        address[] memory _alice = new address[](1);
        _alice[0] = alice;
        kycManager.bulkRevokeKyc(_alice);

        vm.expectRevert(bytes(DISALLOWED_OR_STOP_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(bob, 1);

        // sender banned
        kycManager.bulkBan(_alice);

        vm.expectRevert(bytes(REVOKED_OR_BANNED_MESSAGE));
        vm.prank(alice);
        fundVault.transfer(bob, 1);
    }
}

contract VaultTestTransferNotStrictV2 is FundVaultFactoryV2 {
    function setUp() public {
        alice_deposit(100_000e6);
        kycManager.setStrict(false);
        usdc.mint(bob, 100_000e6);
    }

    function test_Transfers_NotStrict() public {
        // receiver no kyc: ok
        vm.expectEmit();
        emit Transfer(alice, charlie, 1);
        vm.prank(alice);
        fundVault.transfer(charlie, 1);
    }

    function test_Transfers_USSender() public {
        // bobV2 is US
        address[] memory _bob = new address[](1);
        _bob[0] = bob;
        IKycManager.KycType[] memory _us = new IKycManager.KycType[](1);
        _us[0] = IKycManager.KycType.US_KYC;
        kycManager.bulkGrantKyc(_bob, _us);

        make_deposit(bob, 100_000e6);

        // receiver kyc: ok
        vm.expectEmit();
        emit Transfer(bob, alice, 1);
        vm.prank(bob);
        fundVault.transfer(alice, 1);

        // receiver no kyc
        vm.expectRevert(bytes(DISALLOWED_OR_STOP_MESSAGE));
        vm.prank(bob);
        fundVault.transfer(charlie, 1);
    }
}

contract VaultTestDepositV2 is FundVaultFactoryV2 {
    function test_Deposit_Events() public {
        uint256 amount = 100_000e6;

        vm.startPrank(alice);
        usdc.approve(address(fundVault), amount);

        vm.expectEmit();
        emit RequestDeposit(alice, address(usdc), amount);
        assertEq(fundVault.deposit(address(usdc), amount), 0);
        vm.stopPrank();

        vm.prank(operator);
        fundVault.processDeposit(alice, address(usdc), amount, amount);

        assertEq(fundVault.balanceOf(alice), amount);
    }
}

contract VaultTestBalancesV2 is FundVaultFactoryV2 {
    function setUp() public {
        alice_deposit(100_000e6);
    }

    function test_DepositWithdraw() public {
        // Balances after deposit
        uint256 shareBalance = fundVault.balanceOf(alice);
        assertEq(fundVault.totalSupply(), shareBalance);
        assertEq(fundVault._latestNav(), 100_000e6);

        // Preview deposit
        uint256 expectedShares = fundVault.previewDeposit(10_000e6);
        assertEq(expectedShares, 10_000e6);

        // Transfer to custodian
        vm.expectEmit();
        emit TransferToCustodian(fundVault._custodian(), address(usdc), 100_000e6);
        vm.prank(operator);
        fundVault.transferAllToCustodian(address(usdc));

        // Balances after transfer
        assertEq(usdc.balanceOf(custodian), 100_000e6);

        // Set NAV to 105k
        vm.prank(operator);
        fundVault.setFundNav(105_000e6);

        // Return 15k to vault
        vm.prank(custodian);
        usdc.transfer(address(fundVault), 15_000e6);

        // Redeem 10k shares
        uint256 redeemShares = 10_000e6;
        uint256 expectedUsdc = fundVault.previewRedeem(redeemShares);

        // Redeem.1
        vm.prank(alice);
        assertEq(fundVault.redeem(redeemShares, address(usdc)), 0);

        // Redeem.2
        vm.expectEmit();
        emit Transfer(alice, address(0), redeemShares);
        vm.prank(operator);
        fundVault.processRedemption(alice, address(usdc), expectedUsdc, redeemShares);

        // Balances after redeem
        assertGt(usdc.balanceOf(address(fundVault)), 0);
        assertEq(usdc.balanceOf(alice), expectedUsdc);
        assertEq(fundVault.balanceOf(alice), shareBalance - redeemShares);
    }
}

contract VaultTestBetweenOperations is FundVaultFactoryV2 {
    function test_Deposit_TransferBeforeFulfill() public {
        assertEq(usdc.balanceOf(alice), 100_000e6);
        vm.startPrank(alice);
        usdc.approve(address(fundVault), 100_000e6);
        fundVault.deposit(address(usdc), 100_000e6);
        // transfer out: not enough to deposit
        usdc.transfer(bob, 1);
        vm.stopPrank();

        assertLt(usdc.balanceOf(alice), 100_000e6);

        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, 100_000e6 - 1, 100_000e6));
        vm.prank(operator);
        fundVault.processDeposit(alice, address(usdc), 100_000e6, 100_000e6);

        assertEq(fundVault.balanceOf(alice), 0);
    }

    function test_Withdraw_TransferBeforeFulfill() public {
        alice_deposit(100_000e6);

        uint256 balance = fundVault.balanceOf(alice);

        vm.startPrank(alice);
        fundVault.redeem(balance - 10_000e6, address(usdc));
        // transfer out: not enough to redeem
        fundVault.transfer(bob, 50_000e6);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector, balance - 50_000e6, balance - 10_000e6));
        vm.prank(operator);
        fundVault.processRedemption(alice, address(usdc), balance - 10_000e6, balance - 10_000e6);
        assertEq(fundVault.balanceOf(alice), balance - 50_000e6);
    }
}
