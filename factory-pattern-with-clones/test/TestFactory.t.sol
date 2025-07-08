// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import {Test} from "forge-std/Test.sol";
import {TestLogic} from "../src/hedera-clone-test/TestLogic.sol";
import {TestFactory} from "../src/hedera-clone-test/TestFactory.sol";
import {console} from "forge-std/console.sol";

contract TestFactoryTest is Test {
    TestLogic public logic;
    TestFactory public factory;

    function setUp() public {
        logic = new TestLogic();
        factory = new TestFactory(address(logic));
    }

    function testCreateCloneStoresMessage() public {
        string memory msg1 = "Hello clone!";
        address clone = factory.createTest(msg1);

        string memory stored = TestLogic(clone).message();
        assertEq(stored, msg1, "Clone should store the correct message");
    }

    function testMultipleClonesAreIndependent() public {
        address c1 = factory.createTest("First");
        address c2 = factory.createTest("Second");

        console.log("c1", c1);
        console.log("c2", c2);

        assertNotEq(c1, c2, "Each clone should be unique");
        assertEq(TestLogic(c1).message(), "First");
        assertEq(TestLogic(c2).message(), "Second");
    }

    function testClonesArrayUpdated() public {
        factory.createTest("One");
        factory.createTest("Two");

        address[] memory clones = factory.getClones();
        assertEq(clones.length, 2, "Factory should track all clones");
    }
}
