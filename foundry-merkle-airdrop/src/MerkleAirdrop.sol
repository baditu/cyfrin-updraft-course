// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
/**
 * @title MerkleAirdrop
 * @author baditu
 * @notice A merkle airdrop contract that allows for airdropping tokens to a list of addresses based on a merkle root.
 * @dev This contract is used to airdrop tokens to a list of addresses based on a merkle root.
 */

contract MerkleAirdrop is EIP712 {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error MerkleAirdrop__InvalidProof();
    error MerkleAirdrop__AlreadyClaimed();
    error MerkleAirdrop__InvalidSignature();

    using SafeERC20 for IERC20;

    struct AirdropClaim {
        address account;
        uint256 amount;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 private immutable i_merkleRoot;
    address private s_airdropToken;

    mapping(address claimer => bool claimed) private s_hasClaimed;

    bytes32 public constant MESSAGE_TYPEHASH = keccak256("AirdropClaim(address account,uint256 amount)");

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Claim(address indexed _account, uint256 _amount);

    constructor(address _token, bytes32 _merkleRoot) EIP712("MerkleAirdrop", "1") {
        s_airdropToken = _token;
        i_merkleRoot = _merkleRoot;
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /**
     *
     * @param _account The account that is claiming the airdrop
     * @param _amount The amount of tokens the account is claiming
     * @param _proof The proof of the account's inclusion in the merkle tree
     *
     * @notice We can also use the signature as a parameter instead of the v, r, s values
     */
    function claim(address _account, uint256 _amount, bytes32[] calldata _proof, uint8 _v, bytes32 _r, bytes32 _s)
        external
    {
        if (s_hasClaimed[_account]) {
            revert MerkleAirdrop__AlreadyClaimed();
        }

        //check signature
        if (!_isValidSignature(_account, getMessageHash(_account, _amount), _v, _r, _s)) {
            revert MerkleAirdrop__InvalidSignature();
        }

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(_account, _amount))));
        if (!MerkleProof.verify(_proof, i_merkleRoot, leaf)) {
            revert MerkleAirdrop__InvalidProof();
        }
        s_hasClaimed[_account] = true;
        emit Claim(_account, _amount);
        IERC20(s_airdropToken).safeTransfer(_account, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _isValidSignature(address _account, bytes32 digest, uint8 _v, bytes32 _r, bytes32 _s)
        internal
        pure
        returns (bool)
    {
        (address actualSigner,,) = ECDSA.tryRecover(digest, _v, _r, _s);
        return actualSigner == _account;
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getMerkleRoot() external view returns (bytes32) {
        return i_merkleRoot;
    }

    function getAirdropToken() external view returns (address) {
        return s_airdropToken;
    }

    function getMessageHash(address _account, uint256 _amount) public view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(abi.encode(MESSAGE_TYPEHASH, AirdropClaim({account: _account, amount: _amount})))
        );
    }
}
