// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Script, console} from "forge-std/Script.sol";
import {PayfromDelegate} from "../src/PayfromDelegate.sol";

contract DeployPayfromDelegate is Script {
    function run() external {
        vm.startBroadcast();

        PayfromDelegate delegate = new PayfromDelegate();

        vm.stopBroadcast();

        console.log("====================================");
        console.log("Chain ID:", block.chainid);
        console.log("PayfromDelegate deployed to:", address(delegate));
        console.log("====================================");
    }
}
