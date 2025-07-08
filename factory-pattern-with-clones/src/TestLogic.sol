// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract TestLogic is Initializable {
    address public owner;
    string public message;

    function initialize(string memory _message) external initializer {
        owner = msg.sender;
        message = _message;
    }
}
