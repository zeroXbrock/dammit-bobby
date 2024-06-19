// SPDX-License-Identifier: MIT
// Author: Brock Smedley
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/src/utils/JSONParserLib.sol";


library Parser {
    using JSONParserLib for JSONParserLib.Item;
    using JSONParserLib for string;


    /// sauce: https://ethereum.stackexchange.com/a/156916
    function toAddress(string memory s) public pure returns (address pick) {
        bytes memory _bytes = hexStringToAddress(s);
        require(_bytes.length >= 1 + 20, "toAddress_outOfBounds");
        address tempAddress;
        assembly {
            tempAddress := div(
                mload(add(add(_bytes, 0x20), 1)),
                0x1000000000000000000000000
            )
        }
        pick = tempAddress;
    }

    function hexStringToAddress(
        string memory s
    ) public pure returns (bytes memory) {
        bytes memory ss = bytes(s);
        require(ss.length % 2 == 0); // length must be even
        bytes memory r = new bytes(ss.length / 2);
        for (uint i = 0; i < ss.length / 2; ++i) {
            r[i] = bytes1(
                fromHexChar(uint8(ss[2 * i])) *
                    16 +
                    fromHexChar(uint8(ss[2 * i + 1]))
            );
        }

        return r;
    }

    function fromHexChar(uint8 c) public pure returns (uint8) {
        if (bytes1(c) >= bytes1("0") && bytes1(c) <= bytes1("9")) {
            return c - uint8(bytes1("0"));
        }
        if (bytes1(c) >= bytes1("a") && bytes1(c) <= bytes1("f")) {
            return 10 + c - uint8(bytes1("a"));
        }
        if (bytes1(c) >= bytes1("A") && bytes1(c) <= bytes1("F")) {
            return 10 + c - uint8(bytes1("A"));
        }
        return 0;
    }

    function readAddress(
        JSONParserLib.Item memory json,
        string memory key
    ) internal pure returns (address) {
        string memory quotedKey = string(abi.encodePacked('"', key, '"'));
        string memory sAddress = json.at(quotedKey).value().decodeString();
        return toAddress(sAddress);
    }
}