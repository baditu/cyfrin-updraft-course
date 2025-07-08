// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import { TestLogic } from "./TestLogic.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

contract TestFactory {
    address public immutable logic;
    address[] public allClones;

    event CloneCreated(address clone);

    constructor(address _logic) {
        logic = _logic;
    }

    function createTest(string memory message) external returns (address clone) {
        clone = Clones.clone(logic);
        TestLogic(clone).initialize(message);
        allClones.push(clone);
        emit CloneCreated(clone);
    }

    function getClones() external view returns (address[] memory) {
        return allClones;
    }
}
