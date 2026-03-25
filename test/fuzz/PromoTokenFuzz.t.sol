// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PromoToken} from "src/PromoToken.sol";

contract PromoTokenFuzzTest is Test {
    PromoToken internal token;
    address internal admin = address(0xA11CE);
    address internal alice = address(0xB0B);
    address internal bob = address(0xCAFE);

    function setUp() external {
        vm.prank(admin);
        token = new PromoToken(admin, "Casino Promo Credit", "CPC");
    }

    function testFuzzActiveBalanceNeverExceedsBalanceOf(uint96 amount) external {
        uint256 mintAmount = bound(uint256(amount), 1, 1_000_000e18);
        vm.prank(admin);
        token.mintBatch(alice, mintAmount, uint64(block.timestamp + 30 days));

        assertLe(token.activeBalanceOf(alice), token.balanceOf(alice));

        vm.prank(alice);
        token.transfer(bob, mintAmount / 2);

        assertLe(token.activeBalanceOf(alice), token.balanceOf(alice));
        assertLe(token.activeBalanceOf(bob), token.balanceOf(bob));
    }
}
