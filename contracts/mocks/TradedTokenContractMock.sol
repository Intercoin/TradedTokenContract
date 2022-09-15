// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../TradedTokenContract.sol";

contract TradedTokenContractMock is TradedTokenContract {

    using FixedPoint for *;
 
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupIntervalAmount,
        PriceNumDen memory minClaimPrice_,
        address externalToken_,
        PriceNumDen memory externalTokenExchangePrice_,
        uint256 buyTaxMax_,
        uint256 sellTaxMax_
    ) TradedTokenContract(tokenName_, tokenSymbol_, reserveToken_, priceDrop_, lockupIntervalAmount,  minClaimPrice_, externalToken_, externalTokenExchangePrice_, buyTaxMax_, sellTaxMax_)
    {
    }

    function getSqrt(
        uint256 x
    ) 
        public
        pure 
        returns(uint256 result) 
    {
        return sqrt(x);
    }

    function forceSync(
    ) 
        public 
    {
        IUniswapV2Pair(uniswapV2Pair).sync();
    }

    function maxAddLiquidity(
    ) 
        public 
        view 
        //      traded1 -> traded2->priceAverageData
        returns(uint256, uint256, uint256) 
    {  
        return _maxAddLiquidity();
    }

    function getTradedAveragePrice(
    ) 
        public
        view
        returns(FixedPoint.uq112x112 memory)
    {
        return tradedAveragePrice();
    }

    function uniswapReservesSimple(
    ) 
        public 
        view 
        returns(uint256, uint256, uint256)
    {
        return _uniswapReserves();
    }

    function totalInfo(

    )
        public 
        view
        returns(
            uint112 r0, uint112 r1, uint32 blockTimestamp,
            uint price0Cumulative, uint price1Cumulative,
            uint64 timestampLast, uint price0CumulativeLast, uint224 price0Average
        )
    {
        (r0, r1, blockTimestamp) = _uniswapReserves();
        price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();

        timestampLast = pairObservation.timestampLast;
        price0CumulativeLast = pairObservation.price0CumulativeLast;
        
        price0Average = pairObservation.price0Average._x;
        
    }


    
    
    // function uniswapPrices(
    // ) 
    //     //internal  
    //     public
    //     view 
    //     // reserveTraded, reserveReserved, priceTraded, priceReserved, averagePriceTraded, averagePriceReserved, blockTimestamp
    //     returns(uint256, uint256, uint256, uint256, uint256, uint256, uint32)
    // {
    //     // reserveTraded    reserveReserved
    //     (uint256 reserve0, uint256 reserve1, uint32 blockTimestamp) = _uniswapPrices();
        
    //     //if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
    //         return(
    //             reserve0, 
    //             reserve1, 
    //             FRACTION * reserve0 / reserve1,
    //             FRACTION * reserve1 / reserve0,
    //             pairObservation.price0Average.decode(),
    //             pairObservation.price1Average.decode(),
    //             blockTimestamp
    //         );
    //     // } else {
    //     //     return(
    //     //         reserve1, 
    //     //         reserve0, 
    //     //         FRACTION * reserve1 / reserve0,
    //     //         FRACTION * reserve0 / reserve1,
    //     //         FRACTION * price1Average.decode(),
    //     //         FRACTION * price0Average.decode(),
    //     //         blockTimestamp
    //     //     );
    //     // }

    // }


}