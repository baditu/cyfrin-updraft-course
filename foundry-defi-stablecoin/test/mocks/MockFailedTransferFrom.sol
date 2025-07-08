// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockFailedTransferFrom is ERC20, Ownable {
    constructor() ERC20("MockFailedTransferFrom", "MFTF") Ownable(msg.sender) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        // Always return false to simulate failed transferFrom
        return false;
    }
}
