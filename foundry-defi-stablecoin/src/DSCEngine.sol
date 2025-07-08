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
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Baditu
 * @notice The system is designed to be as minimal as possible and have the tokens maintain a 1 token === $1 peg.
 * This stablecoin has the following properties:
 * - Collateral: Exogenous (ETH & BTC)
 * - Algorithmically Stable
 * - Dollar Pegged
 *
 * It is similar to DAI if DAI has no governance, no fees and was only backed by WETH and WBTC.
 *
 * Out DSC system should always be "overcollateralized". At no point, should the value of all collateral <= the $ backed value of all DSC
 *
 * @notice This contract is the core of the DSC System. It handles all the logic for minting and redeeming DSC, as well as deposition and withdrawal of collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error DSCEngine__NeedsBeMoreThanZero();
    error DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorIsGood(uint256 healthFactor);
    error DSCEngine__HealthFactorNotImproved(uint256 healthFactor);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;

    /// @dev Mapping of token address to price feed address
    mapping(address token => address priceFeed) private s_priceFeeds;
    /// @dev Amount of collateral deposited by user
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    /// @dev Amount of DSC minted by user
    mapping(address user => uint256 amountDSCMinted) private s_DSCMinted;
    /// @dev List of collateral tokens accepted by the system
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_DSC;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddress, address DSCAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedAddress.length) {
            revert DSCEngine__TokenAddressAndPriceFeedAddressLengthMismatch();
        }

        // For example ETH / USD, BTC / USD, MKR / USD, etc.
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddress[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_DSC = DecentralizedStableCoin(DSCAddress);
    }

    /**
     * @notice This function allows users to deposit collateral and mint DSC in a single transaction.
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDSCToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the collateral token to deposit
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice This function burns DSC and redeems collateral in a single transaction.
     * @param tokenCollateralAddress The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDSCToBurn The amount of DSC to burn
     */
    function redeemCollateralForDSC(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDSCToBurn)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
    {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @notice they must have more collateral value than the minimum threshold
     * @param tokenCollateralAddress The address of the collateral token to redeem
     * @param amountCollateral The amount of collateral to redeem
     */
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
        isAllowedToken(tokenCollateralAddress)
    {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @notice they must have more collateral value than the minimum threshold
     * @param amountDSCToMint The amount of DSC to mint
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDSCToMint;
        // if they minted too much ($150 DSC, $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_DSC.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amountDSCToBurn) public moreThanZero(amountDSCToBurn) nonReentrant {
        _burnDSC(msg.sender, msg.sender, amountDSCToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // I don't think this would ever hit....
    }

    // $100 ETH backing $50 DSC
    // $20 ETH backing $50 DSC <- DSC isn't worth $1 anymore !!!!

    // $75 ETH backing $50 DSC
    // liquidator take $75 baking and burns off the $50 DSC

    /**
     * @notice Liquidates a user's collateral if their health factor is below the liquidation threshold.
     * @param collateral The address of the collateral token to liquidate.
     * @param user The address of the user whose collateral is being liquidated.
     * The health factor of this user must be below the MIN_HEALTH_FACTOR
     * @param debtToCover The amount of debt to cover in DSC (burn to improve the user's health factor)
     * @notice YOu can partially liquidate a user
     * @notice You will get a reward for liquidating the user, which is the collateral you take.
     * @notice This function working assumes the protocol wii be overcollateralized.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then the liquidator would not be able to get a reward.
     *
     * Follows the Checks-Effects-Interactions (CEI) pattern.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        isAllowedToken(collateral)
        moreThanZero(debtToCover)
        nonReentrant
    {
        // need to check health factor of the user
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsGood(startingUserHealthFactor);
        }

        // burn the user's DSC "debt" and take their collateral
        // BAD USER: $140 ETH, $100 DSC
        // debtToCover = $100
        // $100 of DSC => how much ETH
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateral, debtToCover);
        // And give them a 10% bonus
        // we are giving the liquidator $110 of WETH for $100 of DSC

        // 0.05 ETH * 0.1 = 0.005 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        // note: these are external calls, and below we are checking the health factor of the user => we don't respect CEI, but it is a trade of
        // because otherwise we would have to do a lot of math at first and then do the external calls, which would be more gas expensive.
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDSC(user, msg.sender, debtToCover);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorNotImproved(endingUserHealthFactor);
        }
        _revertIfHealthFactorIsBroken(user);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE & INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        totalDSCMinted = s_DSCMinted[user];
        collateralValueInUSD = getAccountCollateralValue(user);
    }

    /**
     * @notice Calculates the health factor of a user.
     * @dev Health factor is defined as the ratio of the value of collateral to the value of DSC minted.
     * A health factor greater than 1 means the user is safe, while a health factor less than or equal to 1 means the user is at risk of liquidation.
     * @param user The address of the user to check.
     * @return healthFactor The health factor of the user.
     */
    function _healthFactor(address user) internal view returns (uint256) {
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);
        return _calculateHealthFactor(totalDSCMinted, collateralValueInUSD);
    }

    function _calculateHealthFactor(uint256 totalDSCMinted, uint256 collateralValueInUSD)
        internal
        pure
        returns (uint256)
    {
        if (totalDSCMinted == 0) {
            return type(uint256).max; // No DSC minted, health factor is infinite
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDSCMinted;
    }

    /**
     * @notice Reverts if the health factor of the user is below 1.
     * @dev This function checks if the user's health factor is broken, meaning they do not have enough collateral to back the DSC they minted.
     * If the health factor is broken, it reverts the transaction.
     * @param user The address of the user to check.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
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
     * @notice Burns DSC from a user's account.
     * @dev Low-lever internal function that burns DSC from a user's account, do not call unless the function calling
     * it is checking the health factor of the user.
     */
    function _burnDSC(address onBehalfOf, address dscFrom, uint256 amountDSCToBurn) private {
        s_DSCMinted[onBehalfOf] -= amountDSCToBurn;
        bool success = i_DSC.transferFrom(dscFrom, address(this), amountDSCToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_DSC.burn(amountDSCToBurn);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW & PURE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValue) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValue += getUSDValue(token, amount);
        }
    }

    function getUSDValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return uint256(price) * ADDITIONAL_FEED_PRECISION * amount / PRECISION;
    }

    function getTokenAmountFromUSD(address token, uint256 usdAmountInWei) public view returns (uint256) {
        // price of ETH (token)
        // $2000 of ETH. $1000 = 0.5 ETH
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // $ 100e18 * 1e18 / ($2000e8 * 1e10)
        // 005_000_000_000_000_000 => 0.05
        // @note So we need to multiply by PRECISION to get the correct amount in wei, because otherwise we would get a decimal value and in
        // solidity we cannot have decimals.
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDSCMinted, uint256 collateralValueInUSD)
    {
        (totalDSCMinted, collateralValueInUSD) = _getAccountInformation(user);
    }

    function getPrecision() external pure returns (uint256) {
        return PRECISION;
    }

    function calculateHealthFactor(uint256 totalDscMinted, uint256 collateralValueInUsd)
        external
        pure
        returns (uint256)
    {
        return _calculateHealthFactor(totalDscMinted, collateralValueInUsd);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAdditionalFeedPrecision() external pure returns (uint256) {
        return ADDITIONAL_FEED_PRECISION;
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

    function getCollateralTokenPriceFeed(address token) external view returns (address) {
        return s_priceFeeds[token];
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }

    function getLiquidationPrecision() external pure returns (uint256) {
        return LIQUIDATION_PRECISION;
    }

    function getDsc() external view returns (address) {
        return address(i_DSC);
    }
}
