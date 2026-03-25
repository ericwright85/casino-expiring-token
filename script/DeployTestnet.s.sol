// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {PromoToken} from "src/PromoToken.sol";

contract DeployTestnet is Script {
    function run() external returns (PromoToken token) {
        address admin = vm.envAddress("PROMO_TOKEN_ADMIN");
        string memory name_ = vm.envString("PROMO_TOKEN_NAME");
        string memory symbol_ = vm.envString("PROMO_TOKEN_SYMBOL");

        vm.startBroadcast();
        token = new PromoToken(admin, name_, symbol_);
        vm.stopBroadcast();
    }
}
