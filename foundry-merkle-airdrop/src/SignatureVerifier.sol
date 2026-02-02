// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract SignatureVerifier {
    /*//////////////////////////////////////////////////////////////
                           SIMPLE SIGNATURES
    //////////////////////////////////////////////////////////////*/

    /**
     *
     * @param _message The message to get the signer of
     * @notice _v, _r, _s are the components of the signature
     * @param _v The v value of the signature
     * @param _r The r value of the signature
     * @param _s The s value of the signature
     */
    function getSignerSimple(uint256 _message, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        bytes32 hashedMessage = bytes32(_message); // is string, we'd use keccak256(abi.encodePacked(string))
        address signer = ecrecover(hashedMessage, _v, _r, _s);
        return signer;
    }

    function verifySignerSimple(uint256 _message, uint8 _v, bytes32 _r, bytes32 _s, address _signer)
        public
        pure
        returns (bool)
    {
        address actualSigner = getSignerSimple(_message, _v, _r, _s);
        require(actualSigner == _signer);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                            EIP-191
    //////////////////////////////////////////////////////////////*/

    function getSignerEIP191(uint256 _message, uint8 _v, bytes32 _r, bytes32 _s) public view returns (address) {
        /**
         * NOTE: EIP-191 proposed the following format for signed data:
         * 0x19 <1 byte version> <version specific data> <data to sign>
         *
         * Where:
         *
         * 0x19: The prefix.
         *   - This signifies that the data is a signature.
         *   - Its decimal value is 25. 0x19 was chosen because it is not used in any other context.
         *   - It also ensures that the data associated with the signed message cannot be a valid ETH transaction
         *     due to how ETH transactions are encoded.
         *
         * <1 byte version>: The version of "signed data" is used.
         *   - Allows different versions to have different signed data structures.
         *   - Values:
         *     • 0x00: Data with the intended validator.
         *     • 0x01: Structured data - most often used in production apps and associated with EIP-712,
         *              discussed in the next section.
         *     • 0x02: personal_sign messages.
         *
         * <data to sign>: The message intended to be signed.
         */
        bytes1 prefix = bytes1(0x19);
        bytes1 eip191Version = bytes1(0);
        address intendedValidator = address(this);
        bytes32 applicationSpecificData = bytes32(_message);

        // 0x19 <1 byte version> <version specific data> <data to sign>
        bytes32 hashedMessage =
            keccak256(abi.encodePacked(prefix, eip191Version, intendedValidator, applicationSpecificData));

        address signer = ecrecover(hashedMessage, _v, _r, _s);
        return signer;
    }

    function verifySigner191(uint256 message, uint8 _v, bytes32 _r, bytes32 _s, address signer)
        public
        view
        returns (bool)
    {
        address actualSigner = getSignerEIP191(message, _v, _r, _s);
        require(signer == actualSigner);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                                EIP-712
    //////////////////////////////////////////////////////////////*/

    /**
     * NOTE: EIP-712 introduced standardized typed structured data hashing and signing.
     *
     * Using this new standard, the format becomes:
     * 0x19 0x01 <hashStruct(eip712Domain)> <hashStruct(message)>
     *
     * What is a hashStruct?
     *
     * The symbolic definition of a hashStruct is:
     * hashStruct(s : 𝕊) = keccak256(typeHash ‖ encodeData(s))
     *
     * Where:
     * typeHash = keccak256(encodeType(typeOf(s)))
     *
     * A hashStruct is a hash of a struct that includes:
     * - The hash of what the struct looks like (the typeHash)
     * - The typeHash is a hash of the struct type definition
     *
     * For the domainSeparator, the typeHash is based on the EIP712Domain struct below:
     */
    struct EIP712Domain {
        string name;
        string version;
        uint256 chainId;
        address verifyingContract;
        bytes32 salt; // not required
    }

    bytes32 constant EIP712DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract,bytes32 salt)");

    EIP712Domain eip_712_domain_separator_struct;
    bytes32 public immutable i_domain_separator;

    constructor() {
        // Here, we define what our "domain" struct looks like.
        eip_712_domain_separator_struct = EIP712Domain({
            name: "SignatureVerifier", // this can be whatever you want
            version: "1", // this can be whatever you want
            chainId: 1, // ideally this is your chainId
            verifyingContract: address(this), // ideally, you set this as "this", but you could make it whatever contract
                // you want to use to verify signatures
            salt: bytes32(0) // optional field, set to zero
        });

        // Then, we define who is going to verify our signatures? Now that we know what the format of our domain is
        i_domain_separator = keccak256(
            abi.encode(
                EIP712DOMAIN_TYPEHASH,
                keccak256(bytes(eip_712_domain_separator_struct.name)),
                keccak256(bytes(eip_712_domain_separator_struct.version)),
                eip_712_domain_separator_struct.chainId,
                eip_712_domain_separator_struct.verifyingContract,
                eip_712_domain_separator_struct.salt
            )
        );
    }

    // THEN we need to define what our message hash struct looks like.
    struct Message {
        uint256 number;
    }

    bytes32 public constant MESSAGE_TYPEHASH = keccak256("Message(uint256 number)");

    /**
     * NOTE: The EIP-712 signature format can be thought of as:
     *
     * 0x19 0x01 <hashStruct(domainSeparator)> <hashStruct(message)>
     *
     * Where:
     * - 0x19 0x01: EIP-712 prefix (0x19 = EIP-191, 0x01 = structured data version)
     * - hashStruct(domainSeparator): Hash of who verifies this signature and what the verifier looks like
     * - hashStruct(message): Hash of the signed structured message and what the message looks like
     */
    function getSignerEIP712(uint256 _message, uint8 _v, bytes32 _r, bytes32 _s) public view returns (address) {
        bytes1 prefix = bytes1(0x19);
        bytes1 eip712Version = bytes1(0x01); // EIP-712 is version 1 of EIP-191
        bytes32 hashStructOfDomainSeparator = i_domain_separator;

        // now, we can hash our message struct
        bytes32 hashedMessage = keccak256(abi.encode(MESSAGE_TYPEHASH, _message));

        bytes32 digest = keccak256(abi.encodePacked(prefix, eip712Version, hashStructOfDomainSeparator, hashedMessage));
        return ecrecover(digest, _v, _r, _s);
    }

    function verifySigner712(uint256 message, uint8 _v, bytes32 _r, bytes32 _s, address signer)
        public
        view
        returns (bool)
    {
        address actualSigner = getSignerEIP712(message, _v, _r, _s);
        require(signer == actualSigner);
        return true;
    }
}
