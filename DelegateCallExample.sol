// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// NOTE: Deploy this contract first
contract B {
    // NOTE: storage layout must be the same as contract A
    uint256 public num;
    address public sender;
    uint256 public value;

    function setVars(uint256 _num) public payable {
        num = _num;
        sender = msg.sender;
        value = msg.value;
    }
}

contract A {
    uint256 public firstVal;
    address public secondVal;
    uint256 public thirdVal;

    function setVars(address _contract, uint256 _num) public payable {
        // A's storage is set, B is not modified.
        (bool success, bytes memory data) = _contract.delegatecall(abi.encodeWithSignature("setVars(uint256)", _num));
    }

    //Will basically make a "local copy of the function from contract B running it with our storage data(!use correct indexes!)"
    // function setVars(address _contract, uint256 _num) public payable {
    //     storageSlot[0] = _num;
    //     firstValue = _num;
    //     second = msg.sender;
    //     thirdValue = msg.value;
    // }

    //If we didnt have variable names storage slots 1,2,3 would still get updated
    //This still works if your variables in local contract are different to external one.
    //So you can use functions with wrong types. Leading to undefined behavior.
    //For example if firstVal was a bool. ==0  false !=0 is true.
}
