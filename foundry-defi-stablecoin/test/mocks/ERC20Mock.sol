// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    constructor(string memory name, string memory symbol, address owner, uint256 initialSupply)
        ERC20(name, symbol)
        Ownable(owner)
    {
        _mint(owner, initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }
}
