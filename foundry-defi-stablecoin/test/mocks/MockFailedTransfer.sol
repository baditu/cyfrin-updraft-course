// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransfer is ERC20, Ownable {
    constructor() ERC20("MockFailedTransfer", "MFT") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        // Always return false to simulate failed transfer
        return false;
    }
}
