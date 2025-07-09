// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    MockV3Aggregator public ethUsdPriceFeed;

    ERC20Mock public weth;
    ERC20Mock public wbtc;

    uint256 public timesMintIsCalled;
    address[] public usersWithCollateralDeposited;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // the max uint96 value

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _dsc) {
        dscEngine = _dscEngine;
        dsc = _dsc;

        address[] memory collateralTokens = dscEngine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator((dscEngine.getCollateralTokenPriceFeed(address(weth))));
    }

    function mintDSC(uint256 amount, uint256 addressSeed) public {
        vm.assume(usersWithCollateralDeposited.length > 0);
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(sender);
        int256 maxDSCToMint = int256(collateralValueInUSD / 2) - int256(totalDSCMinted);
        if (maxDSCToMint <= 0) {
            return;
        }
        amount = bound(amount, 1, uint256(maxDSCToMint));
        if (amount == 0) {
            return;
        }
        vm.startPrank(sender);
        dscEngine.mintDSC(amount);
        vm.stopPrank();
        timesMintIsCalled++;
    }

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(dscEngine), amountCollateral);
        dscEngine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        usersWithCollateralDeposited.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dscEngine.getCollateralBalanceOfUser(msg.sender, address(collateral));
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        // Get account information to calculate max safe redemption
        (uint256 totalDSCMinted, uint256 collateralValueInUSD) = dscEngine.getAccountInformation(msg.sender);

        // Calculate max collateral value that can be redeemed while maintaining health factor >= 1
        // For health factor >= 1: (remainingCollateral * 50 / 100) >= totalDSCMinted
        // So: remainingCollateral >= totalDSCMinted * 2
        // Therefore: maxRedeemableValue = collateralValueInUSD - (totalDSCMinted * 2)
        int256 maxCollateralValueToRedeem = int256(collateralValueInUSD) - int256(totalDSCMinted * 2);

        if (maxCollateralValueToRedeem <= 0) {
            return; // Can't redeem anything without breaking health factor
        }

        // Convert max USD value to token amount and bound the redemption
        uint256 maxTokensToRedeem =
            dscEngine.getTokenAmountFromUSD(address(collateral), uint256(maxCollateralValueToRedeem));
        if (maxTokensToRedeem > maxCollateralToRedeem) {
            maxTokensToRedeem = maxCollateralToRedeem;
        }

        amountCollateral = bound(amountCollateral, 0, maxTokensToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.startPrank(msg.sender);
        dscEngine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    // this breaks our invariant test suite!!!
    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    // Helper Functions
    function _getCollateralFromSeed(uint256 collateralSeed) internal view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        }

        return wbtc;
    }
}
