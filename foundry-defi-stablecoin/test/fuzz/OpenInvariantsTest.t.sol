// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral
// 2. Getter view functions should never revert <- evergreen invariant

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract OpenInvariantsTest is StdInvariant, Test {
    DeployDSC public deployer;
    DSCEngine public dscEngine;
    DecentralizedStableCoin public dsc;
    HelperConfig public helperConfig;
    address public weth;
    address public wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        // targetContract(address(dscEngine));
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() external view {
        // get the value of all the collateral in protocol
        // compare it to the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUSDValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUSDValue(wbtc, totalWbtcDeposited);

        console.log("Times mint is called: ", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() external view {
        dscEngine.getCollateralBalanceOfUser(msg.sender, address(weth));
        dscEngine.getCollateralBalanceOfUser(msg.sender, address(wbtc));
        dscEngine.getCollateralTokens();
    }
}
