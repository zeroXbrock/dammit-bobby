// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "suave-std/protocols/Builder/Session.sol";
import "suave-std/protocols/EthJsonRPC.sol";
import "suave-std/Test.sol";

import {FormattedOffer} from "../src/interface/IYakRouter.sol";
import "../src/Bob.sol";

struct Deployment {
    address v2Factory;
    address tokenA;
    address tokenB;
    address tokenC;
    address pairAB;
    address pairAC;
    address pairBC;
}

contract BackrunnerEnd2End is Test, SuaveEnabled {
    using OfferUtils for FormattedOffer;

    string constant BUILDER_URL = "execution";
    string constant signerPk =
        "e75efb5cb5fe86353cacf3992da4576a248ecfe11dcf8124e2bbbda2c66a46eb";
    string constant holesky_rpc = "https://ethereum-holesky-rpc.publicnode.com";
    address constant yakrouter_holesky =
        0x985d014DA6e6C781ec3FF77E8Fd48c30174F3d96;
    address constant tokenA = 0x58c65450e9Ea4C8F527534De6762a940F5D8B7aA;

    function init_trading_pairs() public {
        string[] memory deployLiquidity = new string[](1);
        deployLiquidity[0] = "./deployLiquidity.sh";
        vm.ffi(deployLiquidity);

        string[] memory readDeployment = new string[](2);
        readDeployment[0] = "cat";
        readDeployment[1] = "../deployment-test.json";
        bytes memory deployment = vm.ffi(readDeployment);
        console2.log(string(deployment));

        // read json file: deployment-test.json
    }

    function test_init() public {
        init_trading_pairs();
    }

    // function test_run() public {
    //     uint amountIn = 2000000000;

    //     EthJsonRPC jsonrpc = new EthJsonRPC(holesky_rpc);

    //     // 🔍 Find top of the block arb
    //     BobTheBuilder bob = new BobTheBuilder(
    //         yakrouter_holesky,
    //         holesky_rpc,
    //         signerPk
    //     );
    //     FormattedOffer memory offer = bob.findArb(tokenA, amountIn);
    //     uint tob_profit = offer.profit();
    //     console.log("TOB Profit: ", tob_profit);

    //     // 🛠️ Construct tx that extract found arb
    //     TransactionOverrides memory overrides;
    //     overrides.nonce = jsonrpc.nonce(bob.signerAddress());
    //     Transactions.EIP155 memory arbSignedTx = bob.constructArbTx(
    //         offer,
    //         overrides
    //     );

    //     // 👷‍♂️ Block building session
    //     Session session = new Session(BUILDER_URL);
    //     Types.BuildBlockArgs memory buildblockargs;
    //     buildblockargs.timestamp = type(uint64).max; // todo: fill with proper args?
    //     buildblockargs.gasLimit = type(uint64).max;
    //     session.start(buildblockargs);
    //     // Apply arb tx to the builder session
    //     session.addTransaction(arbSignedTx);
    //     // Find arb on the builder session
    //     bytes memory findArbCalldata = bob.findArbCalldata(tokenA, amountIn);
    //     bytes memory result = session.doCall(
    //         yakrouter_holesky,
    //         findArbCalldata
    //     );
    //     FormattedOffer memory offer2 = abi.decode(result, (FormattedOffer));
    //     uint sessionProfit = offer2.profit();
    //     console.log("Session Profit: ", sessionProfit);

    //     // Check that applied tx clears some of the profit
    //     assert(sessionProfit != tob_profit);
    // }
}
