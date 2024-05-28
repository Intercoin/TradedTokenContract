// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStructs {
     
    // struct represent the follow things
    // --- token's `amount` available to claim every `frequency` bucket
    // --- but will decrease by `decrease` fraction every `period`
    struct Emission{
        uint128 amount; // of tokens
        uint32 frequency; // in seconds
        uint32 period; // in seconds
        uint32 decrease; // out of FRACTION 10,000
        int32 priceGainMinimum; // out of FRACTION 10,000
    }

    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }

    struct ClaimSettings {
        PriceNumDen minClaimPrice;
        PriceNumDen minClaimPriceGrow;
    }
}

