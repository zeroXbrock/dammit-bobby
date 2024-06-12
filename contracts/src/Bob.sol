// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Suave} from "suave-std/suavelib/Suave.sol";
import {Suapp} from "suave-std/Suapp.sol";
import {EthJsonRPC} from "suave-std/protocols/EthJsonRPC.sol";
import "suave-std/Transactions.sol";
import {IYakRouter, FormattedOffer, Trade} from "./libs/IYakRouter.sol";

/// Can we arb it? Yes we can!
contract BobTheBuilder is Suapp {
    address immutable yakRouter = 0x1234567890123456789012345678901234567890; // TODO: correct address

    event ArbsFound(bytes[] signedTxs);

    modifier confidential() {
        require(Suave.isConfidential(), "must run confidentially");
        _;
    }

    function signerKey() internal pure returns (string memory) {
        // TODO: get this from ConfStore
        return string(abi.encodePacked(bytes32(0)));
    }

    function profit(
        FormattedOffer memory offer
    ) internal pure returns (uint256) {
        uint256 amountStart = offer.amounts[0];
        uint256 amountEnd = offer.amounts[offer.amounts.length - 1];
        if (amountEnd <= amountStart) {
            return 0;
        } else {
            return amountEnd - amountStart;
        }
    }

    /// "Bubble sort, cuz why not"
    function bubbleSort(
        FormattedOffer[] memory arr
    ) internal pure returns (FormattedOffer[] memory) {
        uint n = arr.length;
        for (uint i = 0; i < n - 1; i++) {
            for (uint j = 0; j < n - i - 1; j++) {
                if (profit(arr[j]) < profit(arr[j + 1])) {
                    (arr[j], arr[j + 1]) = (arr[j + 1], arr[j]);
                }
            }
        }
        return arr;
    }

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

    /// Pull block from confidential store & check yakswap for arbs.
    function findArbs(
        address recipient
    ) public confidential returns (bytes memory) {
        // TODO: pull this from CStore
        address[] memory tokensToCheck = new address[](3);
        tokensToCheck[0] = 0x58c65450e9Ea4C8F527534De6762a940F5D8B7aA;
        tokensToCheck[1] = 0x96748E756073f9a902a60ef8192a4895e78F7489;
        tokensToCheck[2] = 0xE3331E86864dc613f7AcB295d8D89e90AEE3984F;

        FormattedOffer[] memory arbOffers = new FormattedOffer[](
            tokensToCheck.length
        );

        EthJsonRPC eth = new EthJsonRPC(
            "https://ethereum-holesky-rpc.publicnode.com"
        );

        // find possible arbs
        for (uint256 i = 0; i < tokensToCheck.length; i++) {
            address token = tokensToCheck[i];
            bytes memory res = eth.call(
                yakRouter,
                abi.encodeWithSelector(
                    /* findBestPath(
                        uint256 _amountIn,
                        address _tokenIn,
                        address _tokenOut,
                        uint256 _maxSteps
                    )*/
                    IYakRouter.findBestPath.selector,
                    optimalAmountIn(token),
                    token,
                    token,
                    3
                )
            );

            FormattedOffer memory offer = abi.decode(res, (FormattedOffer));
            arbOffers[i] = offer;
        }

        // sort arbs by profit & filter out conflicting paths
        FormattedOffer[] memory finalOffers = filterConflictingPaths(
            bubbleSort(arbOffers)
        );

        Transactions.EIP155[] memory signedArbs = new Transactions.EIP155[](
            finalOffers.length
        );

        // sign arbs
        for (uint256 i = 0; i < finalOffers.length; i++) {
            FormattedOffer memory offer = finalOffers[i];
            /*Trade {
                uint256 amountIn;
                uint256 amountOut;
                address[] path;
                address[] adapters;
            }*/
            Trade memory trade = Trade(
                optimalAmountIn(offer.path[0]),
                optimalAmountIn(offer.path[0]), // [min]amountOut; same as amountIn bc we're arbing
                offer.path,
                offer.adapters
            );
            bytes memory swapCalldata = abi.encodeWithSelector(
                /*swapNoSplit(
                        Trade calldata _trade,
                        address _to,
                        uint256 _fee
                    )*/
                IYakRouter.swapNoSplit.selector,
                trade,
                recipient,
                0
            );
            // bytes memory simRes = Suave.ethcall(yakRouter, swapCalldata);
            Transactions.EIP155Request memory req = Transactions.EIP155Request({
                to: yakRouter,
                data: swapCalldata,
                value: 0,
                gas: 500000,
                gasPrice: 69 gwei,
                chainId: 17000, // hardcoded for holesky, TODO: make dynamic
                nonce: 0 // TODO: get this from reliable source
            });
            Transactions.EIP155 memory signedTxn = Transactions.signTxn(
                req,
                signerKey()
            );
            signedArbs[i] = signedTxn;
        }

        // "send arbs"
        return abi.encodeWithSelector(this.onFindArbs.selector, signedArbs);
    }

    function onFindArbs(bytes[] memory signedArbs) public confidential {
        emit ArbsFound(signedArbs);
    }
}
