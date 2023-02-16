// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../libs/FixedPoint.sol";
import "../libs/TaxesLib.sol";

interface ITradedToken {
    struct Taxes {
        uint16 buyTaxMax;
        uint16 sellTaxMax;
        uint16 holdersMax;
    }
    
    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }

    struct Observation {
        uint64 timestampLast;
        uint256 price0CumulativeLast;
        FixedPoint.uq112x112 price0Average;
    }
    
    struct ClaimSettings {
        PriceNumDen minClaimPrice;
        PriceNumDen minClaimPriceGrow;
    }


}