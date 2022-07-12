// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../Main.sol";

contract MainMock is Main {

    using FixedPoint for *;
    
    constructor(
        address reserveToken_, //” (USDC)
        uint8 granularitySize_,
        uint256 priceDrop_,
        uint256 windowSize_,
        uint64 lockupIntervalAmount,
        PriceNumDen memory minClaimPrice_,
        address externalToken_,
        PriceNumDen memory externalTokenExchangePrice_
    ) Main(reserveToken_, granularitySize_, priceDrop_, windowSize_, lockupIntervalAmount,  minClaimPrice_, externalToken_, externalTokenExchangePrice_)
    {
    }

    function uniswapPricesSimple(
    ) 
        public 
        view 
        returns(uint256, uint256, uint256)
    {
        return _uniswapPrices();
    }
    
    function uniswapPrices(
    ) 
        //internal  
        public
        view 
        // reserveTraded, reserveReserved, priceTraded, priceReserved, averagePriceTraded, averagePriceReserved, blockTimestamp
        returns(uint256, uint256, uint256, uint256, uint256, uint256, uint32)
    {

        (uint256 reserve0, uint256 reserve1, uint32 blockTimestamp) = _uniswapPrices();

        Observation storage firstObservation = getFirstObservationInWindow();

        uint timeElapsed = block.timestamp - firstObservation.timestamp;
// console.log("uniswapPrices:timeElapsed = ", timeElapsed);
// console.log("uniswapPrices:windowSize = ", windowSize);
        require(timeElapsed <= windowSize, "MISSING_HISTORICAL_OBSERVATION");
        // should never happen.
        require(timeElapsed >= windowSize - periodSize * 2, "SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED");

        (uint price0Cumulative, uint price1Cumulative,) = currentCumulativePrices(uniswapV2Pair, uint112(reserve0), uint112(reserve1), blockTimestamp);

        FixedPoint.uq112x112 memory price0Average = FixedPoint.uq112x112(
            uint224((price0Cumulative - firstObservation.price0Cumulative) / timeElapsed)
        );
        FixedPoint.uq112x112 memory price1Average = FixedPoint.uq112x112(
            uint224((price1Cumulative - firstObservation.price1Cumulative) / timeElapsed)
        );
        
        if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
            return(
                reserve0, 
                reserve1, 
                FRACTION * reserve0 / reserve1,
                FRACTION * reserve1 / reserve0,
                FRACTION * price0Average.decode(),
                FRACTION * price1Average.decode(),
                blockTimestamp
            );
        } else {
            return(
                reserve1, 
                reserve0, 
                FRACTION * reserve1 / reserve0,
                FRACTION * reserve0 / reserve1,
                FRACTION * price1Average.decode(),
                FRACTION * price0Average.decode(),
                blockTimestamp
            );
        }

    }


}