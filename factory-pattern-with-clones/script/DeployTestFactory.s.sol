// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
// import {TestLogic} from "../src/hedera-clone-test/TestLogic.sol";
// import {TestFactory} from "../src/hedera-clone-test/TestFactory.sol";

contract DeployTestFactory is Script {
    function run() external {
        vm.startBroadcast();

        TestLogic logic = new TestLogic();
        TestFactory factory = new TestFactory(address(logic));

        console.log("Logic contract deployed at:", address(logic));
        console.log("Factory contract deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
