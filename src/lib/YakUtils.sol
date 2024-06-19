// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../interface/IYakRouter.sol";
import "suave-std/Transactions.sol";


struct TransactionOverrides {
    uint nonce; 
    uint gasLimit;
    uint gasPrice;
    uint chainid;
}

library YakArb {
    using OfferUtils for FormattedOffer;

    uint constant MAX_STEPS = 3;

    function findArbCalldata(
        address baseToken, 
        uint amountIn
    ) internal returns (bytes memory) {
        return abi.encodeWithSelector(
            IYakRouter.findBestPath.selector, 
            amountIn, 
            baseToken, 
            baseToken, 
            MAX_STEPS
        );
    }

    function constructArbTxReq(
        address yakRouter,
        address trader,
        FormattedOffer memory offer, 
        TransactionOverrides memory overrides
    ) internal returns (Transactions.EIP155Request memory signedTx) {
        signedTx = constructSwapTxReq(yakRouter, trader, offer.toTrade(), overrides);
    }

    function constructSwapTxReq(
        address yakRouter,
        address trader,
        Trade memory trade,
        TransactionOverrides memory overrides
    ) internal returns (Transactions.EIP155Request memory) {
        require(overrides.chainid != 0, "chainid must be set");
        bytes memory swapCalldata = abi.encodeWithSelector(
            IYakRouter.swapNoSplit.selector,
            trade,
            trader,
            0
        );
        return Transactions.EIP155Request({
            to: yakRouter,
            data: swapCalldata,
            value: 0,
            gas: 500_000,
            gasPrice: overrides.gasPrice > 0 ? overrides.gasPrice : 10 gwei, 
            chainId: overrides.chainid,
            nonce: overrides.nonce
        });
    }

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
