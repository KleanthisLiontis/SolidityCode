//Get funds from users
//Withdraw funds
//Set a min value

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
//import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
//import "@chainlink/contracts/src/v0.8/Denominations.sol";
import {PriceConverter} from "./PriceConverter.sol";

//Customer errors
error NotOwner();

contract FundMe {
    using PriceConverter for uint256;

    //constant is used for compile time var declaration
    uint256 public constant MINIMUM_USD = 5e18;
    address[] public funders;
    mapping(address => uint256 amountFunded) public addressToAmountFunded;

    //Immutable is set once and then cannot change.
    address public immutable i_owner;

    //auto called when contract is created on chain.
    constructor() {
        i_owner = msg.sender;
    }

    function fund() public payable {
        require(
            msg.value.getConversionRate() >= MINIMUM_USD,
            "You need to spend more ETH!"
        );
        //require(getConversionRate(msg.value) >= minimumUSD,"Send more money pleaze :)");
        funders.push(msg.sender);
        addressToAmountFunded[msg.sender] += msg.value;
    }

    function withdraw() public OnlyOwner {
        //require(msg.sender == owner,"Must be owner");
        for (
            uint256 funderIndex = 0;
            funderIndex < funders.length;
            funderIndex++
        ) {
            address funder = funders[funderIndex];
            addressToAmountFunded[funder] = 0;
        }
        //reset the array.
        funders = new address[](0);
        //actually withdraw the funds - 3 ways to do this.
        /*transfer - will auto revert
        payable(msg.sender).transfer(address(this).balance);
        */
        //send
        /*
        bool sendSuccess = payable(msg.sender).send(address(this).balance);
        require (sendSuccess,"Send Failed");
        */
        //call
        (bool callSuccess, bytes memory dataReturned) = payable(msg.sender)
            .call{value: address(this).balance}("");
        require(callSuccess, "Call Failed");
    }

    function getPrice() public view returns (uint256) {
        //Address - 0x694AA1769357215DE4FAC081bf1f309aDC325306
        //ABI - Interface of contract need to know what functions we can use not how they are implemented
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            0x694AA1769357215DE4FAC081bf1f309aDC325306
        );
        (, int price, , , ) = priceFeed.latestRoundData();
        //Price of eth in terms of USD
        //Number will be without decimals since Sol doesnt handle them well.
        return uint256(price * 1e10);
    }

    function getConversionRate(
        uint256 ethAmount
    ) public view returns (uint256) {
        // 1 ETH?
        // 2000_000000000000000000
        uint256 ethPrice = getPrice();
        // 2000_000000000000000000 * 1_000000000000000000 / 1e18
        uint256 ethAmountInUSD = (ethPrice * ethAmount) / 1e18;
        return ethAmountInUSD;
    }

    //Adds this code to start of function and then rest of code _; position matters
    modifier OnlyOwner() {
        //require(require(msg.sender == i_owner,"Must be owner"));
        if (msg.sender != i_owner) {
            revert NotOwner();
        }
        _;
    }

    receive() external payable {
        fund();
    }

    fallback() external payable {
        fund();
    }
}
