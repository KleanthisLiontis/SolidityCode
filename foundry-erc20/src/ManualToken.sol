// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract ManualToken { 

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    mapping(address => uint256) private s_balances;

    function name() public view returns (string memory) {
        return "Manual Token";
    }
    //function symbol() public view returns (string) {}
    function decimals() public pure returns (uint8) {
        return 18;
    }
    function totalSupply() public pure returns (uint256) {
        return 100 ether; // 10 *10^18
    }
    function balanceOf(address _owner) public view returns (uint256 balance) {
        return s_balances[_owner];
    }
    function transfer(address _to, uint256 _value) public returns (bool success) {
        uint256 previousBalance = s_balances[msg.sender] + s_balances[_to];
        s_balances[msg.sender] -= _value;
        s_balances[_to] += _value;
        //if(balanceof[_from] + balanceOf[_to]  == previousBalance) {
        require(s_balances[msg.sender] + s_balances[_to]  == previousBalance);
        return success;
    }
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {}
//     function approve(address _spender, uint256 _value) public returns (bool success)
//     function allowance(address _owner, address _spender) public view returns (uint256 remaining)
}