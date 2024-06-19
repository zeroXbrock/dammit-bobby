// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "suave-std/protocols/Builder/Session.sol";
import "suave-std/protocols/EthJsonRPC.sol";
import "forge-std/console2.sol";
import "suave-std/Test.sol";

import "../src/interface/IYakRouter.sol";
import "../src/Bob.sol";
import "./lib/DeploymentConfig.sol";


contract BackrunnerEnd2End is Test, SuaveEnabled {
    using OfferUtils for FormattedOffer;

    address constant yakrouter_holesky = 0x985d014DA6e6C781ec3FF77E8Fd48c30174F3d96;
    string constant BUILDER_URL = "execution";
    uint constant HOLESKY_CHAINID = 17000;

    string deploymentPath = "./test/config/deployment-test.json";
    EthJsonRPC jsonrpc;
    address tokenA;
    address tokenB;
    address tokenC;

    function test_run() public {
        string memory signerPK = VM.envString("TRADER_PK");
        Deployment memory deploymentConfig = DeploymentUtils.fromFile(deploymentPath);
        tokenA = deploymentConfig.tokenA;
        tokenB = deploymentConfig.tokenB;
        tokenC = deploymentConfig.tokenC;

        jsonrpc = new EthJsonRPC(BUILDER_URL);
        address[] memory tokensToCheck = new address[](3);
        tokensToCheck[0] = deploymentConfig.tokenA;
        tokensToCheck[1] = deploymentConfig.tokenB;
        tokensToCheck[2] = deploymentConfig.tokenC;
        uint backrunAmount = 0.1 ether;

        // Initialize builder and the building session
        console.log("\n1) Initializing builder and the building session");
        BobTheBuilder bob = new BobTheBuilder(
            yakrouter_holesky,
            signerPK,
            BUILDER_URL,
            tokensToCheck,
            HOLESKY_CHAINID
        );
        Session session = bob.newDefaultBuilderSession();

        // Find TOB arbitrage
        console.log("\n2) Finding TOB arbs");
        FormattedOffer[] memory arbsTOB = bob.findArbsTOB(backrunAmount);
        console2.log("\t* Found", arbsTOB.length, "TOB arbs");
        for (uint i = 0; i < arbsTOB.length; i++) {
            console2.log("\t\t* TOB(after backrun) Arb", i, "with profit", arbsTOB[i].profit());
        }

        // Add trade tx
        console.log("\n3) Adding trade to the builder session");
        uint tradeAmount = 1.9 ether;
        address adapter = 0xc80f61d1bdAbD8f5285117e1558fDDf8C64870FE;
        Transactions.EIP155 memory tradeTx = backrunnableTrade(
            tokenB, 
            tokenA, 
            adapter,
            tradeAmount,
            bob.signerAddress(),
            signerPK
        );
        session.addTransaction(tradeTx);

        console.log("\n4) Finding BOB arbs");
        FormattedOffer[] memory arbsBOB = bob.findArbsForSession(session, backrunAmount);
        console2.log("\t* Found", arbsBOB.length, "BOB arbs");
        for (uint i = 0; i < arbsBOB.length; i++) {
            console2.log("\t\t* BOB Arb", i, "with profit", arbsBOB[i].profit());
        }
        // Add arb tx to the session
        console.log("\n5) Applying BOB arbs to the session");
        TransactionOverrides memory overrides; 
        overrides.nonce = jsonrpc.nonce(bob.signerAddress()) + 1;
        overrides.chainid = HOLESKY_CHAINID;
        bob.addArbToSession(session, arbsBOB[0], overrides);

        console.log("\n6) Finding BOB arbs after backrun was applied");
        FormattedOffer[] memory arbsBOBAfter = bob.findArbsForSession(session, backrunAmount);
        console2.log("\t* Found", arbsBOBAfter.length, "BOB arbs after backrun");
        for (uint i = 0; i < arbsBOBAfter.length; i++) {
            console2.log("\t\t* BOB(after backrun) Arb", i, "with profit", arbsBOBAfter[i].profit());
        }

    }

    function backrunnableTrade(
        address tokenA, 
        address tokenB, 
        address adapter,
        uint amountIn,
        address trader,
        string memory pk
    ) internal returns (Transactions.EIP155 memory) {
        address[] memory adapters = new address[](1);
        adapters[0] = adapter;
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = tokenB;
        Trade memory trade = Trade({
            amountIn: amountIn, 
            adapters: adapters,
            amountOut: 0,
            path: path
        });
        TransactionOverrides memory overrides;
        overrides.nonce = jsonrpc.nonce(trader);
        overrides.chainid = HOLESKY_CHAINID;
        Transactions.EIP155Request memory req = YakArb.constructSwapTxReq(
            yakrouter_holesky, 
            trader, 
            trade, 
            overrides
        );
        return Transactions.signTxn(req, pk);
    }
    
}
