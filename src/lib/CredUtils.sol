// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "suave-std/suavelib/Suave.sol";


library CredentialUtils {
    function getAddressForPk(string memory pk) internal returns (address) {
        bytes32 digest = keccak256(abi.encode("yo"));
        bytes memory sig = Suave.signMessage(abi.encodePacked(digest), Suave.CryptoSignature.SECP256, pk);
        return recoverSigner(digest, sig);
    }

    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(sig.length == 65, "invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) {
            v += 27;
        }
    }
}