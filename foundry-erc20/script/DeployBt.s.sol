// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {BetterToken} from "../src/BetterToken.sol";

contract DeployBt is Script {

    uint256 public constant INITIAL_SUPPLY = 1000 ether;

    function run() external {
        vm.startBroadcast();
        new BetterToken(INITIAL_SUPPLY);
        vm.stopBroadcast();
    }
}