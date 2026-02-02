// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";

import {Vault} from "src/Vault.sol";
import {RebaseToken} from "src/RebaseToken.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public OWNER = makeAddr("owner");
    address public USER = makeAddr("user");
    address public BOB = makeAddr("bob");

    function setUp() public {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(address(rebaseToken));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();

        uint256 startBalance = rebaseToken.balanceOf(USER);

        console.log("Start Balance:", startBalance);
        assertEq(startBalance, amount);

        vm.warp(block.timestamp + 1 hours);

        uint256 middleBalance = rebaseToken.balanceOf(USER);
        console.log("Middle Balance:", middleBalance);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);

        uint256 endBalance = rebaseToken.balanceOf(USER);
        console.log("End Balance:", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.balanceOf(USER), amount);

        vault.redeem(type(uint256).max);

        assertEq(rebaseToken.balanceOf(USER), 0);
        assertEq(address(USER).balance, amount);

        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(USER, depositAmount);
        vm.prank(USER);
        vault.deposit{value: depositAmount}();

        vm.warp(block.timestamp + time);

        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(USER);

        vm.deal(OWNER, balanceAfterSomeTime - depositAmount);
        vm.prank(OWNER);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);

        vm.prank(USER);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(USER).balance;

        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        uint256 userBalance = rebaseToken.balanceOf(USER);
        uint256 bobBalance = rebaseToken.balanceOf(BOB);

        assertEq(userBalance, amount);
        assertEq(bobBalance, 0);

        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        vm.prank(USER);
        rebaseToken.transfer(BOB, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(USER);
        uint256 bobBalanceAfterTransfer = rebaseToken.balanceOf(BOB);

        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(bobBalanceAfterTransfer, amountToSend);

        // check the user interest rate has been inherited (5e10 not 4e10)
        assertEq(rebaseToken.getUserInterestRate(USER), 5e10);
        assertEq(rebaseToken.getUserInterestRate(BOB), 5e10);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.mint(USER, 1e18, rebaseToken.getInterestRate());

        vm.prank(USER);
        vm.expectRevert();
        rebaseToken.burn(USER, 1e18);
    }

    function testGetPrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        assertEq(rebaseToken.getPrincipleBalanceOf(USER), amount);

        vm.warp(block.timestamp + 1 hours);

        assertEq(rebaseToken.getPrincipleBalanceOf(USER), amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(address(rebaseToken), vault.getRebaseTokenAddress());
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint256).max);
        vm.prank(OWNER);
        vm.expectPartialRevert(RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(newInterestRate);

        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
