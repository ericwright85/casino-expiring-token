// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test} from "forge-std/Test.sol";
import {PromoToken} from "src/PromoToken.sol";

contract PromoTokenInvariantTest is StdInvariant, Test {
    PromoToken internal token;
    address internal admin = address(0xA11CE);
    address internal alice = address(0xB0B);

    function setUp() external {
        vm.prank(admin);
        token = new PromoToken(admin, "Casino Promo Credit", "CPC");

        vm.prank(admin);
        token.mintBatch(alice, 100e18, uint64(block.timestamp + 30 days));

        targetContract(address(token));
    }

    function invariant_ActiveNeverExceedsNominalBalance() external view {
        assertLe(token.activeBalanceOf(alice), token.balanceOf(alice));
    }
}
