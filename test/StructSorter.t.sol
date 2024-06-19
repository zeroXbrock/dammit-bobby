// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console2.sol";

struct TestOffer {
    uint256[] amounts;
    address[] path;
    uint256 id;
}

contract StructSorter is Test {
    function profit(TestOffer memory offer) public pure returns (uint256) {
        uint256 amountStart = offer.amounts[0];
        uint256 amountEnd = offer.amounts[offer.amounts.length - 1];
        console2.log("amountStart", amountStart);
        console2.log("amountEnd", amountEnd);
        if (amountEnd <= amountStart) {
            return 0;
        } else {
            return amountEnd - amountStart;
        }
    }

    /// "Bubble sort, cuz why not"
    function bubbleSort(
        TestOffer[] memory arr
    ) public pure returns (TestOffer[] memory) {
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

    function testPathConflicts() public pure {
        address[] memory a = new address[](3);
        a[0] = address(0x1);
        a[1] = address(0x2);
        a[2] = address(0x3);
        address[] memory b = new address[](3);
        b[0] = address(0x4);
        b[1] = address(0x5);
        b[2] = address(0x6);
        require(!pathsDoConflict(a, b), "should not conflict");

        address[] memory c = new address[](3);
        c[0] = address(0x3);
        c[1] = address(0x5);
        c[2] = address(0x6);
        require(pathsDoConflict(a, c), "should conflict");
    }

    function filterConflictingPaths(
        TestOffer[] memory offers
    ) internal pure returns (TestOffer[] memory) {
        TestOffer[] memory filteredOffers = new TestOffer[](offers.length);
        filteredOffers[0] = offers[0];
        for (uint256 i = 1; i < offers.length; i++) {
            TestOffer memory offer = offers[i];
            for (uint256 j = i + 1; j < offers.length; j++) {
                TestOffer memory otherOffer = offers[j];
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
        TestOffer[] memory nonEmptyOffers = new TestOffer[](count);
        for (uint256 i = 0; i < filteredOffers.length; i++) {
            if (filteredOffers[i].path.length > 0) {
                nonEmptyOffers[index] = filteredOffers[i];
                index++;
            }
        }
        return nonEmptyOffers;
    }

    function testSorting() public pure {
        TestOffer[] memory offers = new TestOffer[](3);
        address[] memory path = new address[](2);
        path[0] = address(420);
        path[1] = address(69);
        uint256[] memory n1 = new uint256[](3);
        n1[0] = 10;
        n1[1] = 2;
        n1[2] = 1;
        offers[0] = TestOffer({amounts: n1, path: path, id: 0}); // profit == (1 - 10) == -9 => 0
        uint256[] memory n2 = new uint256[](3);
        n2[0] = 4;
        n2[1] = 5;
        n2[2] = 6;
        offers[1] = TestOffer({amounts: n2, path: path, id: 1}); // profit == (6 - 4) == 2
        uint256[] memory n3 = new uint256[](3);
        n3[0] = 7;
        n3[1] = 8;
        n3[2] = 19;
        offers[2] = TestOffer({amounts: n3, path: path, id: 2}); // profit == (19 - 7) == 12

        TestOffer[] memory sortedOffers = bubbleSort(offers);

        for (uint256 i = 0; i < sortedOffers.length - 1; i++) {
            require(
                profit(sortedOffers[i]) >= profit(sortedOffers[i + 1]),
                "should be sorted by profit (desc)"
            );
        }

        TestOffer[] memory filteredPathOffers = filterConflictingPaths(offers);
        require(
            filteredPathOffers.length == 1,
            "should have only 1 offer after filtering"
        );
    }
}
