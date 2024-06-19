// SPDX-License-Identifier: MIT
// Author: Brock Smedley
pragma solidity ^0.8.0;

import {JSONParserLib} from "solady/src/utils/JSONParserLib.sol";
import {Parser} from "./Parser.sol";


interface ICheats {
    function ffi(string[] calldata) external returns (bytes memory);
    function envString(string calldata key) external returns (string memory);
}
ICheats constant VM = ICheats(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

struct Deployment {
    address v2Factory;
    address tokenA;
    address tokenB;
    address tokenC;
    address pairAB;
    address pairAC;
    address pairBC;
}

library DeploymentUtils {
    using Parser for *;

    function fromFile(string memory path) internal returns (Deployment memory) {
        // read deployment file
        string[] memory readDeployment = new string[](2);
        readDeployment[0] = "cat";
        readDeployment[1] = path;
        bytes memory deployment = VM.ffi(readDeployment);
        string memory sDeployment = string(deployment);

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

}

function init_trading_pairs() returns (Deployment memory) {
    // string memory pk = cheats.envString("YAKDEPLOYER_PK");

    // // run deployment script
    // string[] memory deployLiquidity = new string[](4);
    // deployLiquidity[0] = "./deployLiquidity.sh";
    // deployLiquidity[1] = string(abi.encode(factory));
    // deployLiquidity[2] = pk;
    // deployLiquidity[3] = string(abi.encode(yakrouter_holesky));
    // vm.ffi(deployLiquidity);

    
}

// function test_init() public {
//     Deployment memory d = init_trading_pairs();
//     console.log("v2Factory:\t", d.v2Factory);
//     console.log("tokenA:\t", d.tokenA);
//     console.log("tokenB:\t", d.tokenB);
//     console.log("tokenC:\t", d.tokenC);
//     console.log("pairAB:\t", d.pairAB);
//     console.log("pairAC:\t", d.pairAC);
//     console.log("pairBC:\t", d.pairBC);
// }