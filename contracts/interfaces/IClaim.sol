// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IClaim {

    struct ClaimStruct {
        uint256 amount;
        uint256 lastActionTime;
    }
    struct PriceNumDen {
        uint256 numerator;
        uint256 denominator;
    }
    struct ClaimSettings {
        address claimingToken;
        PriceNumDen claimingTokenExchangePrice;
        uint32 claimFrequency;
    }

    function claim(uint256 amount, address account) external;   
    function availableToClaim() external view returns(uint256 tradedTokenAmount);
    function wantToClaim(uint256 amount) external;
    function getTradedToken() external view returns(address);

}
