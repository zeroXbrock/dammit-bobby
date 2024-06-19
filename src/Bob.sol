// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "suave-std/protocols/Builder/Session.sol";
import "suave-std/protocols/EthJsonRPC.sol";
import "suave-std/Transactions.sol";
import "suave-std/Gateway.sol";
import "suave-std/Suapp.sol";
import "./lib/CredUtils.sol";
import "./lib/YakUtils.sol";


/// Can we arb it? Yes we can!
contract BobTheBuilder is Suapp {
    using OfferUtils for FormattedOffer;
    
    uint constant MAX_STEPS = 3;
    address immutable remoteYakRouterAddress;
    address public immutable signerAddress;
    EthJsonRPC immutable jsonrpc;
    IYakRouter immutable yakRouter;
    uint immutable chainId;
    address[] tokensToCheck;
    string builderUrl;
    string signerPk;

    constructor(
        address _yakRouter, 
        string memory _signerPk,
        string memory _builderUrl, 
        address[] memory _tokensToCheck,
        uint _chainId
    ) {
        chainId = _chainId;
        jsonrpc = new EthJsonRPC(_builderUrl);
        remoteYakRouterAddress = _yakRouter;
        tokensToCheck = _tokensToCheck;
        builderUrl = _builderUrl;
        signerPk = _signerPk; // todo: in prod use confidential store
        signerAddress = CredentialUtils.getAddressForPk(_signerPk);

        address gateway = address(new Gateway(_builderUrl, _yakRouter));
        yakRouter = IYakRouter(gateway);
    }

    function newDefaultBuilderSession() public returns (Session) {
        Session session = new Session(builderUrl);
        Types.BuildBlockArgs memory buildblockargs;
        buildblockargs.timestamp = type(uint64).max;
        buildblockargs.gasLimit = type(uint64).max;
        session.start(buildblockargs);
        return session;
    }

    function buildBlockAndBackrun(
        Transactions.EIP155[] memory signedTxs,
        uint backrunAmountIn
    ) public returns (Session session) {
        session = newDefaultBuilderSession();
        for (uint i = 0; i < signedTxs.length; i++) {
            session.addTransaction(signedTxs[i]);
        }
        backrunSession(session, backrunAmountIn);
        // todo: build and submit a block
    }

    function backrunSession(
        Session session, 
        uint amountIn
    ) public {
        FormattedOffer[] memory arbs = findArbsForSession(session, amountIn);
        addArbsToSession(session, arbs);
    }

    function findArbsForSession(Session session, uint amountIn) public returns (FormattedOffer[] memory) {
        FormattedOffer[] memory arbOffers = new FormattedOffer[](tokensToCheck.length);
        for (uint256 i = 0; i < tokensToCheck.length; i++) {
            FormattedOffer memory offer = findArbForSession(session, tokensToCheck[i], amountIn);
            if (offer.profit() > 0)
                arbOffers[i] = offer;
        }
        return filterConflictingPaths(bubbleSort(arbOffers));
    }

    function findArbsTOB(uint amountIn) public returns (FormattedOffer[] memory offers) {
        FormattedOffer[] memory arbOffers = new FormattedOffer[](tokensToCheck.length);
        for (uint256 i = 0; i < tokensToCheck.length; i++) {
            FormattedOffer memory offer = yakRouter.findBestPath(
                amountIn, 
                tokensToCheck[i], 
                tokensToCheck[i], 
                MAX_STEPS
            );
            if (offer.profit() > 0)
                arbOffers[i] = offer;
        
        }
        return filterConflictingPaths(bubbleSort(arbOffers));
    }

    function findArbForSession(
        Session session, 
        address token, 
        uint amountIn
    ) public returns (FormattedOffer memory offer) {
        bytes memory data = YakArb.findArbCalldata(token, amountIn);
        bytes memory result = session.doCall(remoteYakRouterAddress, data);
        offer = abi.decode(result, (FormattedOffer));
    }

    function addArbsToSession(Session session, FormattedOffer[] memory offers) public {
        TransactionOverrides memory overrides;
        overrides.nonce = jsonrpc.nonce(signerAddress);
        overrides.chainid = chainId; // todo: do rpc call instead

        for (uint256 i = 0; i < offers.length; i++) {
            addArbToSession(session, offers[i], overrides);
            overrides.nonce++;
        }
    }

    function addArbToSession(
        Session session, 
        FormattedOffer memory offer,
        TransactionOverrides memory overrides
    ) public {
        Transactions.EIP155Request memory txn = YakArb.constructArbTxReq(
            remoteYakRouterAddress, 
            signerAddress, 
            offer, 
            overrides
        );
        Transactions.EIP155 memory signedTxn = Transactions.signTxn(txn, signerPk);
        session.addTransaction(signedTxn);
    }

    /// "Bubble sort, cuz why not"
    function bubbleSort(
        FormattedOffer[] memory arr
    ) internal pure returns (FormattedOffer[] memory) {
        uint n = arr.length;
        for (uint i = 0; i < n - 1; i++) {
            for (uint j = 0; j < n - i - 1; j++) {
                if (arr[j].profit() < arr[j + 1].profit()) {
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

}