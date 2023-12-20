// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SimpleStorage} from "./SimpleStorage.sol";

//Child of SimpleStorage
contract AddFiveStorage is SimpleStorage {
    //Also need to change in parent contract add virtual to function.
    function store(uint256 _new_number) public override {
        my_favourite_number = _new_number + 5;
    }
}
