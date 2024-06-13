// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {EthJsonRPC} from "suave-std/protocols/EthJsonRPC.sol";
import {Suave} from "suave-std/suavelib/Suave.sol";
import {Suapp} from "suave-std/Suapp.sol";
import {Gateway} from "suave-std/Gateway.sol";
import "suave-std/Transactions.sol";

import {IYakRouter, FormattedOffer, Trade} from "./interface/IYakRouter.sol";


struct TransactionOverrides {
    uint nonce; 
    uint gasLimit;
    uint gasPrice;
    uint chainid;
}


/// Can we arb it? Yes we can!
contract BobTheBuilder is Suapp {
    using OfferUtils for FormattedOffer;
    
    IYakRouter immutable yakRouter;
    address immutable remoteYakRouterAddress;
    address public immutable signerAddress;
    string signerPk;
    uint constant MAX_STEPS = 3;
    uint constant HOLESKY_CHAINID = 17000;

    event ArbsFound(Transactions.EIP155[] signedTxs);

    modifier confidential() {
        require(Suave.isConfidential(), "must run confidentially");
        _;
    }

    constructor(address _yakRouter, string memory _remoteRpc, string memory _signerPk) {
        remoteYakRouterAddress = _yakRouter;
        signerPk = _signerPk;
        signerAddress = Utils.getAddressForPk(_signerPk);
        address gateway = address(new Gateway(_remoteRpc, _yakRouter));
        yakRouter = IYakRouter(gateway);
    }

    function findArb(
        address baseToken, 
        uint amountIn
    ) public returns (FormattedOffer memory) {
        return yakRouter.findBestPath(amountIn, baseToken, baseToken, MAX_STEPS);
    }

    function findArbCalldata(
        address baseToken, 
        uint amountIn
    ) public returns (bytes memory) {
        return abi.encodeWithSelector(yakRouter.findBestPath.selector, amountIn, baseToken, baseToken, MAX_STEPS);
    }

    function constructArbTx(FormattedOffer memory offer, TransactionOverrides memory overrides) public returns (Transactions.EIP155 memory signedTx) {
        bytes memory swapCalldata = abi.encodeWithSelector(
            IYakRouter.swapNoSplit.selector,
            offer.toTrade(),
            signerAddress,
            0
        );
        Transactions.EIP155Request memory txRequest = Transactions.EIP155Request({
            to: remoteYakRouterAddress,
            data: swapCalldata,
            value: 0,
            gas: 500_000,
            gasPrice: overrides.gasPrice > 0 ? overrides.gasPrice : 10 gwei, 
            chainId: overrides.chainid > 0 ? overrides.chainid : HOLESKY_CHAINID,
            nonce: overrides.nonce > 0 ? overrides.nonce : 0 // TODO: get this from reliable source
        });
        signedTx = Transactions.signTxn(txRequest, signerPk);
    }

    // function signerKey() internal pure returns (string memory) {
    //     // TODO: get this from ConfStore
    //     return
    //         "0x91ab9a7e53c220e6210460b65a7a3bb2ca181412a8a7b43ff336b3df1737ce12";
    // }

    // function profit(
    //     FormattedOffer memory offer
    // ) internal pure returns (uint256) {
    //     uint256 amountStart = offer.amounts[0];
    //     uint256 amountEnd = offer.amounts[offer.amounts.length - 1];
    //     if (amountEnd <= amountStart) {
    //         return 0;
    //     } else {
    //         return amountEnd - amountStart;
    //     }
    // }

    // /// "Bubble sort, cuz why not"
    // function bubbleSort(
    //     FormattedOffer[] memory arr
    // ) internal pure returns (FormattedOffer[] memory) {
    //     uint n = arr.length;
    //     for (uint i = 0; i < n - 1; i++) {
    //         for (uint j = 0; j < n - i - 1; j++) {
    //             if (profit(arr[j]) < profit(arr[j + 1])) {
    //                 (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
    //             }
    //         }
    //     }
    //     return arr;
    // }

    function pathsDoConflict(
        address[] memory a,
        address[] memory b
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < a.length; i++) {
            for (uint256 j = 0; j < b.length; j++) {
                if (a[i] == b[j]) {
                    return true;
                }
            }
        }
        return false;
    }

    /// Filter out offers that have conflicting paths.
    /// MUST BE PRE-SORTED.
    function filterConflictingPaths(
        FormattedOffer[] memory offers
    ) internal pure returns (FormattedOffer[] memory) {
        FormattedOffer[] memory filteredOffers = new FormattedOffer[](
            offers.length
        );
        filteredOffers[0] = offers[0];
        for (uint256 i = 1; i < offers.length; i++) {
            FormattedOffer memory offer = offers[i];
            for (uint256 j = i + 1; j < offers.length; j++) {
                FormattedOffer memory otherOffer = offers[j];
                if (!pathsDoConflict(offer.path, otherOffer.path)) {
                    filteredOffers[i] = offer;
                }
            }
        }
        // now identify empty paths and return a new array with only the non-empty paths
        uint256 count = 0;
        for (uint256 i = 0; i < filteredOffers.length; i++) {
            if (filteredOffers[i].path.length > 0) {
                count++;
            }
        }
        uint256 index = 0;
        FormattedOffer[] memory nonEmptyOffers = new FormattedOffer[](count);
        for (uint256 i = 0; i < filteredOffers.length; i++) {
            if (filteredOffers[i].path.length > 0) {
                nonEmptyOffers[index] = filteredOffers[i];
                index++;
            }
        }
        return nonEmptyOffers;
    }

    function optimalAmountIn(address token) internal pure returns (uint256) {
        // TODO: solve for this using quadratic search or something similar
        token; // silence unused var warning
        return 1 ether;
    }

    // /// Pull block from confidential store & check yakswap for arbs.
    // function findArbs(
    //     address recipient
    // ) public confidential returns (bytes memory) {
    //     // TODO: pull this from CStore
    //     address[] memory tokensToCheck = new address[](3);
    //     tokensToCheck[0] = 0x58c65450e9Ea4C8F527534De6762a940F5D8B7aA;
    //     tokensToCheck[1] = 0x96748E756073f9a902a60ef8192a4895e78F7489;
    //     tokensToCheck[2] = 0xE3331E86864dc613f7AcB295d8D89e90AEE3984F;

    //     FormattedOffer[] memory arbOffers = new FormattedOffer[](
    //         tokensToCheck.length
    //     );

    //     EthJsonRPC eth = new EthJsonRPC(
    //         "https://ethereum-holesky-rpc.publicnode.com"
    //     );

    //     // find possible arbs
    //     for (uint256 i = 0; i < tokensToCheck.length; i++) {
    //         address token = tokensToCheck[i];
    //         bytes memory res = eth.call(
    //             yakRouter,
    //             abi.encodeWithSelector(
    //                 /* findBestPath(
    //                     uint256 _amountIn,
    //                     address _tokenIn,
    //                     address _tokenOut,
    //                     uint256 _maxSteps
    //                 )*/
    //                 IYakRouter.findBestPath.selector,
    //                 optimalAmountIn(token),
    //                 token,
    //                 token,
    //                 3
    //             )
    //         );

    //         FormattedOffer memory offer = abi.decode(res, (FormattedOffer));
    //         arbOffers[i] = offer;
    //     }

    //     // sort arbs by profit & filter out conflicting paths
    //     FormattedOffer[] memory finalOffers = filterConflictingPaths(
    //         bubbleSort(arbOffers)
    //     );

    //     Transactions.EIP155[] memory signedArbs = new Transactions.EIP155[](
    //         finalOffers.length
    //     );

    //     // sign arbs
    //     for (uint256 i = 0; i < finalOffers.length; i++) {
    //         FormattedOffer memory offer = finalOffers[i];
    //         /*Trade {
    //             uint256 amountIn;
    //             uint256 amountOut;
    //             address[] path;
    //             address[] adapters;
    //         }*/
    //         Trade memory trade = Trade(
    //             optimalAmountIn(offer.path[0]),
    //             optimalAmountIn(offer.path[0]), // [min]amountOut; same as amountIn bc we're arbing
    //             offer.path,
    //             offer.adapters
    //         );
    //         bytes memory swapCalldata = abi.encodeWithSelector(
    //             /*swapNoSplit(
    //                     Trade calldata _trade,
    //                     address _to,
    //                     uint256 _fee
    //                 )*/
    //             IYakRouter.swapNoSplit.selector,
    //             trade,
    //             recipient,
    //             0
    //         );

    //         Transactions.EIP155Request memory req = Transactions.EIP155Request({
    //             to: yakRouter,
    //             data: swapCalldata,
    //             value: 0,
    //             gas: 500000,
    //             gasPrice: 69 gwei,
    //             chainId: 17000, // hardcoded for holesky, TODO: make dynamic
    //             nonce: 0 // TODO: get this from reliable source
    //         });
    //         Transactions.EIP155 memory signedTxn = Transactions.signTxn(
    //             req,
    //             signerKey()
    //         );
    //         signedArbs[i] = signedTxn;
    //     }

        // "send arbs"
    //     emit ArbsFound(signedArbs);
    //     return abi.encodeWithSelector(this.onFindArbs.selector, signedArbs);
    // }

    function onFindArbs(
        Transactions.EIP155[] memory signedArbs
    ) public emitOffchainLogs {}
}


library OfferUtils {

    function profit(
        FormattedOffer memory offer
    ) internal pure returns (uint256) {
        if (offer.amounts.length == 0)
            return 0;
        uint256 amountStart = offer.amounts[0];
        uint256 amountEnd = offer.amounts[offer.amounts.length - 1];
        if (amountEnd > amountStart)
            return amountEnd - amountStart; 
    }

    function toTrade(
        FormattedOffer memory offer
    ) internal pure returns (Trade memory trade) {
        trade.amountIn = offer.amounts[0];
        trade.amountOut = offer.amounts[offer.amounts.length-1];
        trade.path = offer.path;
        trade.adapters = offer.adapters;
    }

}

library Utils {
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