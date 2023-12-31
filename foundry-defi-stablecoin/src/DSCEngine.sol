// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {DecentralisedStableCoin} from "./DecentralisedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from
    "lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @author   . Kleanthis Liontis
 * @title    . DSCEngine
 * @notice   . Very loosely based on the MakerDAO DSS (DAI) system. This contract is the core of the DSC System. Handles all
 * the logic redeeming and minting DSC, depositing and withdrawals.
 * The system is designed to be minimal and have tokens maintain the peg of == $1
 * Collateral - Exogenous (ETH,BTC)
 * Pegged to USD
 * Algorithmically stablised.
 */
contract DSCEngine is ReentrancyGuard {
    ///////////////////
    ////   Errors  ////
    ///////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 _healthFactor);
    error DSCEngine_MintFailed();

    ////////////////////////////
    ////   State variables  ////
    ////////////////////////////
    uint256 private constant ADDIOTIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized.
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;

    ///////////////////
    //// Events    ////
    ///////////////////
    event CollateralDepossited(address indexed user, address indexed token, uint256 indexed amount);

    ///////////////////
    //// Modifiers ////
    ///////////////////
    modifier moreThanZero(uint256 _amount) {
        if (_amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address _tokenAddress) {
        if (s_priceFeeds[_tokenAddress] == address(0)) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    ////////////////////////////
    //// External Functions ////
    ////////////////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        //USD Price feeds: ETH/USD,BTC/USD.
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        for (uint256 i = 0; i < priceFeedAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            //needed to get users collatValues
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralisedStableCoin(dscAddress);
    }
    //Want to be overcollateralised in case weth and wbtc tanks.
    //

    /**
     * @notice  . Follows CEI
     * param  . amountDscToMint The amount of decentralized stablecoin to mint
     * notice . They must have more collateral value than the minimum threshold
     */
    function depositCollateralAndMintDsc() external {}

    /**
     * @notice  . Follows CEI
     * @param   tokenCollateralAddress  . The address of the token to deposit as collateral.
     * @param   amountCollateral  . The amount of collateral deposited.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDepossited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral() external {}

    function redeemCollateralForDsc() external {}

    /**
     * @notice  . //1.Check if collateral value > DSC amount.
     * @param   amountDscToMint  . The amount of DSC to mint
     */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //check for overmint again.
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc() external {}

    function liquidate() external {}

    function gasHealthFactor() external {}

    ////////////////////////////////////
    //Private and Internal Functions///
    ////////////////////////////////////

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /* Returns how close to liquidation a user is
     * If a user goes below 1, then they can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        //
        uint256 collateralAdjustedForThreshhold = (collateralValueInUsd * LIQUIDATION_THRESHOLD);
        /*/ LIQUIDATION_PRECISION;*/
        // 100 ETH * 50 = 50000/100 = 500;
        // 150 ETH /100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = 75 -> from getUsdValue -> 75/100 < 1 so position liquidated.
        return (collateralAdjustedForThreshhold / totalDscMinted); //(150/100) we want to be overfunded
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        //Check health factor(do they have enough collateral)
        //Revert if they do not
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////
    ///Public and Private View Funcs//
    //////////////////////////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        //loop through users collat tokens and get they ammount they deposited.
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        //1 ETH = 2.3k dollars
        //The price from ChainL will be 2300 * 1e8; Check their site.
        //Amount will be 1e18 -> Have to standardise and then divide by 1e18
        return ((uint256(price) * ADDIOTIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}
