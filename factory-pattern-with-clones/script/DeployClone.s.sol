// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {Script} from "forge-std/Script.sol";
import {TestFactory} from "../src/hedera-clone-test/TestFactory.sol";
import {console} from "forge-std/console.sol";

contract DeployClone is Script {
    function run() external {
        vm.startBroadcast();
        address factoryAddress = 0x8A7fa94487d0d0460550e5F3F80A663c39Ac8B10;

        TestFactory factory = TestFactory(factoryAddress);

        address clone1 = factory.createTest("Hello from Romania");
        console.log("Clone 1 created at:", clone1);

        address clone2 = factory.createTest("Salut din Transilvania");
        console.log("Clone 2 created at:", clone2);

        vm.stopBroadcast();
    }
}
