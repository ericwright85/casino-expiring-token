// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PromoToken} from "src/PromoToken.sol";
import {BatchTypes} from "src/types/BatchTypes.sol";

contract PromoTokenTest is Test {
    PromoToken internal token;

    address internal admin = address(0xA11CE);
    address internal alice = address(0xB0B);
    address internal bob = address(0xCAFE);
    address internal carol = address(0xD00D);

    function setUp() external {
        vm.prank(admin);
        token = new PromoToken(admin, "Casino Promo Credit", "CPC");
    }

    function testMintCreatesBatchAndActiveBalance() external {
        vm.prank(admin);
        uint256 batchId = token.mintBatch(alice, 100e18, uint64(block.timestamp + 7 days));

        assertEq(batchId, 1);
        assertEq(token.balanceOf(alice), 100e18);
        assertEq(token.activeBalanceOf(alice), 100e18);

        BatchTypes.BatchInfo memory batch = token.getBatch(batchId);
        assertEq(batch.batchId, batchId);
        assertEq(batch.originalRecipient, alice);
        assertEq(batch.originalAmount, 100e18);
    }

    function testTransferUsesOldestUnexpiredFIFO() external {
        vm.startPrank(admin);
        token.mintBatch(alice, 50e18, uint64(block.timestamp + 1 days));
        token.mintBatch(alice, 70e18, uint64(block.timestamp + 5 days));
        vm.stopPrank();

        vm.prank(alice);
        token.transfer(bob, 60e18);

        BatchTypes.WalletBatchView[] memory aliceBatches = token.getWalletBatches(alice);
        assertEq(aliceBatches[0].amount, 0);
        assertEq(aliceBatches[1].amount, 60e18);

        BatchTypes.WalletBatchView[] memory bobBatches = token.getWalletBatches(bob);
        assertEq(bobBatches.length, 2);
        assertEq(bobBatches[0].batchId, 1);
        assertEq(bobBatches[0].amount, 50e18);
        assertEq(bobBatches[1].batchId, 2);
        assertEq(bobBatches[1].amount, 10e18);
    }

    function testExpiredCannotTransfer() external {
        vm.prank(admin);
        token.mintBatch(alice, 25e18, uint64(block.timestamp + 1 hours));

        vm.warp(block.timestamp + 1 hours + 1);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1e18);

        assertEq(token.activeBalanceOf(alice), 0);
    }

    function testTransferFromRespectsExpiry() external {
        vm.startPrank(admin);
        token.mintBatch(alice, 40e18, uint64(block.timestamp + 4 days));
        vm.stopPrank();

        vm.prank(alice);
        token.approve(carol, 40e18);

        vm.prank(carol);
        token.transferFrom(alice, bob, 30e18);

        assertEq(token.balanceOf(bob), 30e18);
        assertEq(token.activeBalanceOf(bob), 30e18);
    }

    function testPauseBlocksTransfersAndUnpauseRestores() external {
        vm.startPrank(admin);
        token.mintBatch(alice, 20e18, uint64(block.timestamp + 1 days));
        token.pause();
        vm.stopPrank();

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1e18);

        vm.prank(admin);
        token.unpause();

        vm.prank(alice);
        token.transfer(bob, 1e18);
        assertEq(token.balanceOf(bob), 1e18);
    }
}
