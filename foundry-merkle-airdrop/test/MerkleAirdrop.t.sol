// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {MerkleAirdrop} from "../src/MerkleAirdrop.sol";
import {BadoneToken} from "../src/BadoneToken.sol";
import {ZkSyncChainChecker} from "@foundry-devops/ZkSyncChainChecker.sol";
import {DeployMerkleAirdrop} from "../script/DeployMerkleAirdrop.s.sol";

contract MerkleAirdropTest is ZkSyncChainChecker, Test {
    MerkleAirdrop public merkleAirdrop;
    BadoneToken public airdropToken;

    bytes32 public constant MERKLE_ROOT = 0xaa5d581231e596618465a56aa0f5870ba6e20785fe436d5bfb82b08662ccc7c4;
    uint256 public constant AMOUNT = 25 ether;
    uint256 public constant AMOUNT_TO_MINT = AMOUNT * 4;
    bytes32[] public PROOF;
    address gasPayer;
    address user;
    uint256 userPrivateKey;

    function setUp() public {
        if (!isZkSyncChain()) {
            DeployMerkleAirdrop deployer = new DeployMerkleAirdrop();
            (merkleAirdrop, airdropToken) = deployer.deployMerkleAirdrop();
        } else {
            airdropToken = new BadoneToken();
            merkleAirdrop = new MerkleAirdrop(address(airdropToken), MERKLE_ROOT);
            airdropToken.mint(airdropToken.owner(), AMOUNT_TO_MINT);
            airdropToken.transfer(address(merkleAirdrop), AMOUNT_TO_MINT);
        }
        (user, userPrivateKey) = makeAddrAndKey("user");
        gasPayer = makeAddr("gasPayer");
        PROOF.push(0x0fd7c981d39bece61f7499702bf59b3114a90e66b51ba2c53abdf7b62986c00a);
        PROOF.push(0xe5ebd1e1b5a5478a944ecab36a9a954ac3b6b8216875f6524caa7a1d87096576);
    }

    function test_UsersCanClaim() public {
        uint256 initialBalance = airdropToken.balanceOf(user);
        bytes32 digest = merkleAirdrop.getMessageHash(user, AMOUNT);

        // sign a message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // gasPayer calls claim using the signed message
        vm.prank(gasPayer);
        merkleAirdrop.claim(user, AMOUNT, PROOF, v, r, s);

        uint256 endingBalance = airdropToken.balanceOf(user);
        console.log("Ending Balance: ", endingBalance);
        assertEq(endingBalance, initialBalance + AMOUNT);
    }
}
