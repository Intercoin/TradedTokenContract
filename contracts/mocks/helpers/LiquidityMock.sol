// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../../helpers/Liquidity.sol";

contract LiquidityMock is Liquidity {

    constructor(
        address token0_,
        address token1_,
        address uniswapPair_,
        bool token01_,
        uint256 priceDrop_,
        address liquidityLib_,
        IStructs.Emission memory emission_,
        IStructs.ClaimSettings memory claimSettings_
    ) 
        Liquidity(token0_, token1_, uniswapPair_, token01_, priceDrop_, liquidityLib_, emission_, claimSettings_)
    {
        
    }

    function setEmissionAmount(uint128 amount) public {
        emission.amount = amount;
    }

    function setEmissionFrequency(uint32 frequency) public {
        emission.frequency = frequency;
    }

    function setEmissionPeriod(uint32 period) public {
        emission.period = period;
    }

    function setEmissionDecrease(uint32 decrease) public {
        emission.decrease = decrease;
    }

    function setEmissionPriceGainMinimum(int32 priceGainMinimum) public {
        emission.priceGainMinimum = priceGainMinimum;
    }

    function sqrt(uint256 x) public pure returns (uint256 result) {
        return _sqrt(x);
    }

    function maxAddLiquidity()
        public
        view
        returns (
            //      traded1 -> traded2->priceAverageData
            uint256,
            uint256,
            uint256
        )
    {
        return _maxAddLiquidity();
    }

    function setRestrictClaiming(IStructs.PriceNumDen memory newMinimumPrice) public {

        lastMinClaimPriceUpdatedTime = uint64(block.timestamp);
            
        claimSettings.minClaimPrice.numerator = newMinimumPrice.numerator;
        claimSettings.minClaimPrice.denominator = newMinimumPrice.denominator;
    }

    function getMinClaimPriceUpdatedTime() public pure returns(uint64) {
        return MIN_CLAIM_PRICE_UPDATED_TIME;
    }
}
