// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../Main.sol";

contract MainMock is Main {

    using FixedPoint for *;
    
    constructor(
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint256 windowSize_,
        uint64 lockupIntervalAmount,
        PriceNumDen memory minClaimPrice_,
        address externalToken_,
        PriceNumDen memory externalTokenExchangePrice_
    ) Main(reserveToken_, priceDrop_, windowSize_, lockupIntervalAmount,  minClaimPrice_, externalToken_, externalTokenExchangePrice_)
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
        // reserveTraded    reserveReserved
        (uint256 reserve0, uint256 reserve1, uint32 blockTimestamp) = _uniswapPrices();
        
        //if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
            return(
                reserve0, 
                reserve1, 
                FRACTION * reserve0 / reserve1,
                FRACTION * reserve1 / reserve0,
                pairObservation.price0Average.decode(),
                pairObservation.price1Average.decode(),
                blockTimestamp
            );
        // } else {
        //     return(
        //         reserve1, 
        //         reserve0, 
        //         FRACTION * reserve1 / reserve0,
        //         FRACTION * reserve0 / reserve1,
        //         FRACTION * price1Average.decode(),
        //         FRACTION * price0Average.decode(),
        //         blockTimestamp
        //     );
        // }

    }


}