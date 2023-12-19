// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;


contract SimpleStorage {

    bool has_favourite_number = true; //initialises to false
    //defaults to 256 ints/unts if not specified
    uint internal my_favourite_number = 88; //initialises to 0
    string favourite_number_string = "eighty-eight";
    int favourite_int = -88;
    //address myAddress = 0xaB1
    bytes32 favBytes32 = "cat";
    //uint256[] list_of_fav_nums;
    struct Person {
        uint256 favourite_number;
        string name;
    }

    Person public pat = Person(7,"Pat");
    Person public misty = Person(21,"Misty");

    //dynamic
    Person[] public list_of_people;//[]
    //Static - Max 3 peeps.
    //Person[3] public list_of_people;//[]

    mapping(string => uint256) public name_to_fav_number;

    //calldata,memory,storage - Memory temp data that can be changed after passing it || calldata temp data cannot be modified || storage is perm data that cannot be modified
    //structs mapping and arrays need memory. String needs memory or calldata.
    function add_to_list(string memory _name, uint256 _fav_number) public{
        list_of_people.push(Person(_fav_number,_name));
        name_to_fav_number[_name] = _fav_number;
    }

    function store(uint256 _fav_number) public {
        my_favourite_number = _fav_number;
        //retrieve();
        //favourite_number = favourite_number + 1;
    }

    //view returns data from state, pure returns hardcoded value
    /*functions blue in UI since they dont use gas,
    however if used in other functions they will still increase costs!*/
    function retrieve() public view returns(uint256){
        return my_favourite_number;
    }
}

contract SimpleStorage2 {}
contract SimpleStorage3 {}