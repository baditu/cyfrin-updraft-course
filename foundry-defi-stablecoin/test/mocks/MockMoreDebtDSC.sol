// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockV3Aggregator} from "./MockV3Aggregator.sol";

contract MockMoreDebtDSC is ERC20Burnable, Ownable {
    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();

    address mockAggregator;

    constructor(address _mockAggregator) ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {
        mockAggregator = _mockAggregator;
    }

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        if (amount <= 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(to, amount);
        return true;
    }

    function getEthValue() external view returns (uint256) {
        (, int256 price,,,) = MockV3Aggregator(mockAggregator).latestRoundData();
        return uint256(price);
    }
}
