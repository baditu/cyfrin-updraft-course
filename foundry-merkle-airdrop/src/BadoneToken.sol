// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title BadoneToken
 * @author baditu
 * @notice A badone token contract that allows for airdropping tokens to a list of addresses based on a merkle root.
 * @dev This contract is used to airdrop tokens to a list of addresses based on a merkle root.
 */
contract BadoneToken is ERC20, Ownable {
    constructor() ERC20("BadoneToken", "BDT") Ownable(msg.sender) {}

    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
    }
}
