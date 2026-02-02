// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {BadoneToken} from "../src/BadoneToken.sol";

contract DeployMerkleAirdrop is Script {
    bytes32 private constant MERKLE_ROOT = 0xaa5d581231e596618465a56aa0f5870ba6e20785fe436d5bfb82b08662ccc7c4;
    uint256 private constant AMOUNT_TO_TRANSFER = 4 * 25 * 1e18;

    function run() external returns (MerkleAirdrop, BadoneToken) {
        return deployMerkleAirdrop();
    }

    function deployMerkleAirdrop() public returns (MerkleAirdrop, BadoneToken) {
        vm.startBroadcast();
        BadoneToken badoneToken = new BadoneToken();
        MerkleAirdrop merkleAirdrop = new MerkleAirdrop(address(badoneToken), MERKLE_ROOT);
        badoneToken.mint(badoneToken.owner(), AMOUNT_TO_TRANSFER);
        badoneToken.transfer(address(merkleAirdrop), AMOUNT_TO_TRANSFER);
        vm.stopBroadcast();

        return (merkleAirdrop, badoneToken);
    }
}
