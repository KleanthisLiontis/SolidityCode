//Get funds from users
//Withdraw funds
//Set a min value

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
//import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
//import "@chainlink/contracts/src/v0.8/Denominations.sol";
import {PriceConverter} from "./PriceConverter.sol";

contract FundMe{
    using PriceConverter for uint256;

    uint256 public constant MINIMUM_USD = 5e18;
    address[] public funders;
    mapping(address => uint256 amountFunded)public addressToAmountFunded;

    function fund() public payable{

        require(msg.value.getConversionRate() >= MINIMUM_USD, "You need to spend more ETH!");
        //require(getConversionRate(msg.value) >= minimumUSD,"Send more money pleaze :)");
        funders.push(msg.sender);
        addressToAmountFunded[msg.sender] = addressToAmountFunded[msg.sender] + msg.value;
    }

    function withdraw() public {}

    function getPrice() public view returns(uint256){
        //Address - 0x694AA1769357215DE4FAC081bf1f309aDC325306
        //ABI - Interface of contract need to know what functions we can use not how they are implemented
        AggregatorV3Interface priceFeed = AggregatorV3Interface(0x694AA1769357215DE4FAC081bf1f309aDC325306);
        (, int price,,,) = priceFeed.latestRoundData();
        //Price of eth in terms of USD
        //Number will be without decimals since Sol doesnt handle them well.
        return uint256(price * 1e10);
    }
    
    function getConversionRate(uint256 ethAmount) public view returns (uint256){
        // 1 ETH?
        // 2000_000000000000000000
        uint256 ethPrice = getPrice();
        // 2000_000000000000000000 * 1_000000000000000000 / 1e18
        uint256 ethAmountInUSD = (ethPrice * ethAmount) / 1e18;
        return ethAmountInUSD;
    }


}