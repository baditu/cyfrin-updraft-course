// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {BasicNft} from "src/BasicNft.sol";
import {DeployBasicNft} from "script/DeployBasicNft.s.sol";

contract BasicNftTest is Test {
    DeployBasicNft public deployer;
    BasicNft public basicNft;
    address public USER = makeAddr("user");
    string public constant PUG =
        "ipfs://bafybeig37ioir76s7mg5oobetncojcm3c3hxasyd4rvid4jqhy4gkaheg4/?filename=0-PUG.json";

    function setUp() public {
        deployer = new DeployBasicNft();
        basicNft = deployer.run();
    }

    function testNameIsCorrect() public view {
        string memory expectedName = "Dogie";
        string memory actualName = basicNft.name();

        assert(keccak256(abi.encodePacked(expectedName)) == keccak256(abi.encodePacked(actualName)));
        assertEq(actualName, expectedName, "NFT name is incorrect");
    }

    function testCanMintAndHaveABalance() public {
        vm.prank(USER);
        basicNft.mintNft(PUG);

        assertEq(basicNft.balanceOf(USER), 1, "User should have a balance of 1 after minting");
        assertEq(
            keccak256(abi.encodePacked(basicNft.tokenURI(0))),
            keccak256(abi.encodePacked(PUG)),
            "Token URI should match the minted NFT"
        );
    }
}
