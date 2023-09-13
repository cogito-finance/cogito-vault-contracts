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
import "./mock/FundVaultFactory.sol";
import "./mock/USDC.sol";

contract VaultTestRevert is FundVaultFactory {
    function test_Fulfill_RevertWhenNotOracle() public {
        vm.expectRevert("Source must be the oracle of the request");
        vm.prank(alice);
        fundVault.fulfill(bytes32(0), 0);
    }

    function test_Deposit_RevertWhenNotOwner() public {
        vm.expectRevert("receiver must be caller");
        fundVault.deposit(100_000e6, alice);
    }

    function test_Deposit_RevertWhenNoKyc() public {
        vm.expectRevert("user has no kyc");
        vm.prank(charlie);
        fundVault.deposit(100_000e6, charlie);
    }

    function test_Deposit_RevertWhenLessThanMinimum() public {
        vm.startPrank(alice);
        vm.expectRevert("amount < minimum deposit");
        fundVault.deposit(100e6, alice);

        vm.expectRevert("amount < minimum initial deposit");
        fundVault.deposit(10_000e6, alice);
        vm.stopPrank();
    }

    function test_Withdraw_RevertWhenNotOwner() public {
        vm.expectRevert("receiver must be caller");
        fundVault.withdraw(1, alice, alice);
    }

    function test_Withdraw_RevertWhenNoShares() public {
        vm.startPrank(alice);
        vm.expectRevert("withdraw more than balance");
        fundVault.withdraw(1, alice, alice);
    }

    function test_WithdrawQueue_RevertWhenEmpty() public {
        vm.startPrank(operator);
        vm.expectRevert("queue is empty");
        fundVault.requestWithdrawalQueue();
    }

    function test_Withdraw_RevertWhenLessThanMinimum() public {
        alice_deposit(100_000e6);
        vm.prank(alice);
        vm.expectRevert("amount < minimum withdraw");
        fundVault.withdraw(1, alice, alice);
    }
}

contract VaultTestTransfer is FundVaultFactory {
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
    }
}

contract VaultTestDeposit is FundVaultFactory {
    function test_Deposit_Events() public {
        uint256 amount = 100_000e6;

        nextRequestId();
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

        assertGt(fundVault.balanceOf(alice), 0);
    }
}

contract VaultTestBalances is FundVaultFactory {
    function setUp() public {
        alice_deposit(100_000e6);
    }

    function test_DepositWithdraw() public {
        // Balances after deposit
        uint256 shareBalance = fundVault.balanceOf(alice);
        assertEq(fundVault.totalSupply(), shareBalance);
        assertEq(fundVault._latestOffchainNAV(), 0);
        assertEq(fundVault.vaultNetAssets(), 99_950_000_000);
        assertEq(fundVault.totalAssets(), 99_950_000_000);
        assertEq(fundVault.combinedNetAssets(), 99_950_000_000);
        assertEq(fundVault.excessReserves(), 94_952_500_000);
        assertEq(usdc.balanceOf(feeReceiver), 50_000_000);

        vm.prank(operator);
        fundVault.transferExcessReservesToTreasury();

        // Balances after transfer
        assertEq(usdc.balanceOf(treasury), 94_952_500_000);
        assertEq(fundVault.totalAssets(), 4_997_500_000);
        assertEq(fundVault.vaultNetAssets(), 4_997_500_000);
        assertEq(fundVault.combinedNetAssets(), 4_997_500_000);
        assertEq(fundVault._onchainFee(), 0);
        assertEq(fundVault._offchainFee(), 0);

        // Advance epoch
        nextRequestId();
        vm.expectEmit();
        emit RequestAdvanceEpoch(operator, getRequestId());
        vm.prank(operator);
        fundVault.requestAdvanceEpoch();

        // Set NAV to 95k
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), 94_952_500_000);

        // Balances after fee accrual
        assertEq(fundVault._latestOffchainNAV(), 94_952_500_000);
        assertEq(fundVault._onchainFee(), 13_691);
        assertEq(fundVault._offchainFee(), 1_300_719);
        assertEq(fundVault.vaultNetAssets(), 4_996_185_590);
        assertEq(fundVault.totalAssets(), 4_997_500_000);
        assertEq(fundVault.combinedNetAssets(), 99_950_000_000 - 13_691 - 1_300_719);

        // Claim fees
        vm.prank(operator);
        fundVault.claimOnchainServiceFee(type(uint256).max);
        assertEq(usdc.balanceOf(feeReceiver), 50_000_000 + 13_691);
        assertEq(fundVault._onchainFee(), 0);
        vm.prank(operator);
        fundVault.claimOffchainServiceFee(type(uint256).max);
        assertEq(usdc.balanceOf(feeReceiver), 50_000_000 + 13_691 + 1_300_719);
        assertEq(fundVault._offchainFee(), 0);
        assertEq(fundVault.vaultNetAssets(), 4_996_185_590);
        assertEq(fundVault.totalAssets(), 4_996_185_590);
        assertEq(fundVault.previewWithdraw(fundVault.combinedNetAssets()), fundVault.totalSupply());

        // Withdraw 10k, ~half should be available instant
        uint256 wantShares = fundVault.previewWithdraw(10_000e6);
        uint256 actualShares = fundVault.previewWithdraw(4_996_185_590);

        // Withdraw.1
        nextRequestId();
        vm.prank(alice);
        assertEq(fundVault.withdraw(wantShares, alice, alice), 0);

        // Withdraw.2
        vm.expectEmit();
        emit Transfer(alice, address(0), actualShares);
        vm.expectEmit();
        emit Transfer(alice, address(fundVault), wantShares - actualShares);
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), 94_952_500_000);

        // Balances after withdraw
        assertEq(fundVault.totalAssets(), 0);
        assertEq(usdc.balanceOf(alice), 4_996_185_590);
        assertEq(fundVault.balanceOf(alice), shareBalance - wantShares);
        (, uint256 withdrawAmt,) = fundVault.getUserEpochInfo(alice, 1);
        assertEq(withdrawAmt, 10_000e6);
        assertEq(fundVault.getWithdrawalQueueLength(), 1);

        // Attempt to process queue: no change in assets
        nextRequestId();
        vm.expectEmit();
        emit RequestWithdrawalQueue(operator, getRequestId());
        vm.prank(operator);
        fundVault.requestWithdrawalQueue();
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), 94_952_500_000);

        // Balances should not change
        assertEq(fundVault.totalAssets(), 0);
        assertEq(usdc.balanceOf(alice), 4_996_185_590);
        assertEq(fundVault.getWithdrawalQueueLength(), 1);

        // Attempt to process queue: after moving 10k from offchain to vault
        vm.prank(treasury);
        usdc.transfer(address(fundVault), 10_000e6);

        nextRequestId();
        vm.prank(operator);
        fundVault.requestWithdrawalQueue();
        vm.prank(oracle);
        fundVault.fulfill(getRequestId(), 84_952_500_000);

        // Balances after completing withdraw
        assertApproxEqAbs(fundVault.totalAssets(), 4_996_185_590, 10);
        assertApproxEqAbs(usdc.balanceOf(alice), 10_000e6, 10);
        assertEq(fundVault.getWithdrawalQueueLength(), 0);
        assertEq(fundVault.balanceOf(alice), shareBalance - wantShares);
        assertEq(fundVault.totalSupply(), shareBalance - wantShares);
        assertEq(fundVault.previewWithdraw(fundVault.combinedNetAssets()), fundVault.totalSupply());
    }
}
