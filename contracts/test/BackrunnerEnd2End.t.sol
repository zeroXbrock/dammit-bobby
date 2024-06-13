// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "suave-std/protocols/Builder/Session.sol";
import "suave-std/protocols/EthJsonRPC.sol";
import "suave-std/Test.sol";

import {FormattedOffer} from "../src/interface/IYakRouter.sol";
import "../src/Bob.sol";
import {JSONParserLib} from "solady/src/utils/JSONParserLib.sol";

struct Deployment {
    address v2Factory;
    address tokenA;
    address tokenB;
    address tokenC;
    address pairAB;
    address pairAC;
    address pairBC;
}

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

contract BackrunnerEnd2End is Test, SuaveEnabled {
    using OfferUtils for FormattedOffer;
    using JSONParserLib for JSONParserLib.Item;
    using JSONParserLib for string;
    using Parser for JSONParserLib.Item;

    string constant BUILDER_URL = "execution";
    string constant signerPk =
        "e75efb5cb5fe86353cacf3992da4576a248ecfe11dcf8124e2bbbda2c66a46eb";
    string constant holesky_rpc = "https://ethereum-holesky-rpc.publicnode.com";
    address constant yakrouter_holesky =
        0x985d014DA6e6C781ec3FF77E8Fd48c30174F3d96;
    address constant tokenA = 0x58c65450e9Ea4C8F527534De6762a940F5D8B7aA;

    function init_trading_pairs() public returns (Deployment memory) {
        // run deployment script
        string[] memory deployLiquidity = new string[](1);
        deployLiquidity[0] = "./deployLiquidity.sh";
        vm.ffi(deployLiquidity);

        // read deployment file
        string[] memory readDeployment = new string[](2);
        readDeployment[0] = "cat";
        readDeployment[1] = "../deployment-test.json";
        bytes memory deployment = vm.ffi(readDeployment);
        string memory sDeployment = string(deployment);
        console2.log(sDeployment);

        JSONParserLib.Item memory json = JSONParserLib.parse(sDeployment);
        address v2Factory = json.readAddress("v2Factory");
        address tokenAyyy = json.readAddress("tokenA");
        address tokenB = json.readAddress("tokenB");
        address tokenC = json.readAddress("tokenC");
        address pairAB = json.readAddress("pairAB");
        address pairAC = json.readAddress("pairAC");
        address pairBC = json.readAddress("pairBC");

        return
            Deployment({
                v2Factory: v2Factory,
                tokenA: tokenAyyy,
                tokenB: tokenB,
                tokenC: tokenC,
                pairAB: pairAB,
                pairAC: pairAC,
                pairBC: pairBC
            });
    }

    function test_init() public {
        Deployment memory d = init_trading_pairs();
        console.log("v2Factory:\t", d.v2Factory);
        console.log("tokenA:\t", d.tokenA);
        console.log("tokenB:\t", d.tokenB);
        console.log("tokenC:\t", d.tokenC);
        console.log("pairAB:\t", d.pairAB);
        console.log("pairAC:\t", d.pairAC);
        console.log("pairBC:\t", d.pairBC);
    }

    function test_run() public {
        uint amountIn = 2000000000;

        EthJsonRPC jsonrpc = new EthJsonRPC(holesky_rpc);

        // 🔍 Find top of the block arb
        BobTheBuilder bob = new BobTheBuilder(
            yakrouter_holesky,
            holesky_rpc,
            signerPk
        );
        FormattedOffer memory offer = bob.findArb(tokenA, amountIn);
        uint tob_profit = offer.profit();
        console.log("TOB Profit: ", tob_profit);

        // 🛠️ Construct tx that extract found arb
        TransactionOverrides memory overrides;
        overrides.nonce = jsonrpc.nonce(bob.signerAddress());
        Transactions.EIP155 memory arbSignedTx = bob.constructArbTx(
            offer,
            overrides
        );

        // 👷‍♂️ Block building session
        Session session = new Session(BUILDER_URL);
        Types.BuildBlockArgs memory buildblockargs;
        buildblockargs.timestamp = type(uint64).max; // todo: fill with proper args?
        buildblockargs.gasLimit = type(uint64).max;
        session.start(buildblockargs);
        // Apply arb tx to the builder session
        session.addTransaction(arbSignedTx);
        // Find arb on the builder session
        bytes memory findArbCalldata = bob.findArbCalldata(tokenA, amountIn);
        bytes memory result = session.doCall(
            yakrouter_holesky,
            findArbCalldata
        );
        FormattedOffer memory offer2 = abi.decode(result, (FormattedOffer));
        uint sessionProfit = offer2.profit();
        console.log("Session Profit: ", sessionProfit);

        // Check that applied tx clears some of the profit
        assert(sessionProfit != tob_profit);
    }
}
