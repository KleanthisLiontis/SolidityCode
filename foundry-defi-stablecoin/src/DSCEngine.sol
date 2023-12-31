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
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    ////////////////////////////
    ////   State variables  ////
    ////////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant FEED_PRECISION = 1e8;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized.
    uint256 private constant LIQUIDATION_BONUS = 10; //Means 10% bonus
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

    mapping(address token => address priceFeed) private s_priceFeeds; //tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralisedStableCoin private immutable i_dsc;

    ///////////////////
    //// Events    ////
    ///////////////////
    event CollateralDepossited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed reedemedFrom, address indexed reedemedTo, address indexed token, uint256 amount
    );

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
     * @param  tokenCollateralAddress The address of the token to deposit as collateral.
     * @param  amountCollateral The amount of collateral to deposit
     * @param  amountDscToMint The amount of decentralized stablecoin to mint
     * @notice The function will deposit your collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice  . Follows CEI
     * @param   tokenCollateralAddress  . The address of the token to deposit as collateral.
     * @param   amountCollateral  . The amount of collateral deposited.
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
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

    //CEI: check effects interactions.
    //1. Health factor must be over 1 AFTER collateral, pulled.
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        //100-1000 (revert)
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param  tokenCollateralAddress The address of the token to deposit as collateral.
     * @param  amountCollateral The amount of collateral to deposit
     * @param  amountDscToBurn The amount of decentralized stablecoin to burn
     * This function burns DSC and redeems underlying collateral in one function.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        //redeem collateral already checks health factor so I wont put it twice.
    }

    /**
     * @notice  . //1.Check if collateral value > DSC amount.
     * @param   amountDscToMint  . The amount of DSC to mint
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //check for overmint again.
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine_MintFailed();
        }
    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        //Same here should never be needed I think.
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*
     * @param collateral: The ERC20 token address of the collateral you're using to make the protocol solvent again.
     * This is collateral that you're going to take from the user who is insolvent.
     * In return, you have to burn your DSC to pay off their debt, but you don't pay off your own.
     * @param user: The user who is insolvent. They have to have a _healthFactor below MIN_HEALTH_FACTOR
     * @param debtToCover: The amount of DSC you want to burn to cover the user's debt.
     *
     * @notice: You can partially liquidate a user.
     * @notice: You will get a 10% LIQUIDATION_BONUS for taking the users funds.
     * @notice: This function working assumes that the protocol will be roughly 150% overcollateralized in order for this to work.
     * @notice: A known bug would be if the protocol was only 100% collateralized, we wouldn't be able to liquidate anyone.
     * For example, if the price of the collateral plummeted before anyone could be liquidated.
     *  Follows CEI: Checks,effects interactions.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        //Check users HF
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }
        //Burn DSC debt they have and take their collateral.
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        // Also give them a 10% bonus to incentivize. Giving the liquidator $ 110WETH for $100 DSC.
        // another feature to liquidate in the event the protocol becomes insolvent should be implemented
        // Sweep extra ammounts into treasury

        //0.05ETH * .1 =  0.005. Getting 0.055ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = bonusCollateral + tokenAmountFromDebtCovered;
        //When we redeem should be same person, when we liquidate address should be whoever it paying for bad debts.
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        //We need to burn DSC
        _burnDsc(debtToCover, user, msg.sender);

        //Need to check healthfactor
        uint256 endingHealthFactor = _healthFactor(user);
        //Check we are not messing lenders healthfactor.
        if (endingHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        //Checking we dont mess up the liquidators health factor as well.
        _revertIfHealthFactorIsBroken(msg.sender);
    }

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

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @dev     . Function calling this should do healthcheck.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        //Hypothetically undreachable but condition here just in case
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
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
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        //price of ETH token? Dollars/ETH
        //$2000 / ETH. -> 1000/ETH = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        //BRACKETS FOR MATHS ARE VERY MUCH NEEDED
        return ((usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION));
    }
}
