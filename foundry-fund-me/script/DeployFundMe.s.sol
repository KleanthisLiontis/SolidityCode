// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {HelperConfig} from "./HelperConfig.s.sol";
import {FundMe} from "../src/FundMe.sol";
import {Script} from "forge-std/Script.sol";

contract DeployFundMe is Script{
    function run() external returns (FundMe, HelperConfig) {
            HelperConfig helperConfig = new HelperConfig(); // This comes with our mocks!
            address priceFeed = helperConfig.activeNetworkConfig();

            vm.startBroadcast();
            FundMe fundMe = new FundMe(priceFeed);
            vm.stopBroadcast();
            return (fundMe, helperConfig);
    }
}
