// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {DeployBt} from "../script/DeployBt.s.sol";
import {BetterToken} from "../src/BetterToken.sol";

interface MintableToken {
    function mint(address, uint256) external;
}


contract betterTokenTest is StdCheats, Test {

    uint256 BOB_STARTING_AMOUNT = 100 ether;
    BetterToken public ourToken;
    Deploy public deployer;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    uint256 public constant STARTING_BALANCE = 100 ether;

    function setUp() public {
        deployer = new DeployBt();
        ourToken = deployer.run();

        vm.prank(address(deployer));
        ourToken.transfer(bob,STARTING_BALANCE);
    }

    function testBobBalance() public {
        assertEq(STARTING_BALANCE, ourToken.balanceOf(bob));
    }

        function testInitialSupply() public {
        assertEq(ourToken.totalSupply(), deployer.INITIAL_SUPPLY());
    }

    function testUsersCantMint() public {
        vm.expectRevert();
        MintableToken(address(ourToken)).mint(address(this), 1);
    }

    function testAllowances() public {
        uint256 initialAllowance = 1000;

        //Bob approves alice to spend tokens on her behalf
        vm.prank(bob);
        ourToken.approve(alice,initialAllowance);

        uint256 tranferAmount = 500;

        vm.prank(alice);
        //from x to y if approved
        ourToken.transferFrom(bob,alice,transferAmount);
        //directly 
        //bt.transfer(alice,transferAmount);
        assertEq(ourToken.balanceOf(alice), tranferAmount);
        assertEq(ourToken.balanceOf(bob), STARTING_BALANCE - tranferAmount);
    }
}
