// // SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DSCEngine} from "../../../src/DSCEngine.sol";
import {DecentralisedStableCoin} from "../../../src/DecentralisedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantsTets is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralisedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        //Will use handler for more sophisticated data entry instead of dscEngine directly.
        //targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view {
        //get value of collateral in the protocol, compare to dsc debt.
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = ERC20Mock(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total supply: ", totalSupply);
        //Calling ghost variable.
        console.log("Times mint called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue > totalSupply);
    }

    //MUST USE (put all getters in here -- no args)
    //forge inspect DSCEngine methods...very helpful to add getter infront of name for this.
    function invariant_gettersShouldNotRevert() public view {
        dscEngine.getPrecision();
        dscEngine.getAdditionalFeedPrecision();
        dscEngine.getLiquidationBonus();
        dscEngine.getLiquidationPrecision();
        dscEngine.getMinHealthFactor();
        dscEngine.getCollateralTokens();
        dscEngine.getDsc();
    }
}
