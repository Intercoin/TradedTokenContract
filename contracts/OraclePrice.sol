// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
import "./libs/FixedPoint.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

import "./interfaces/IOraclePrice.sol";

import "hardhat/console.sol";
abstract contract OraclePrice  {

    using FixedPoint for *;

    address internal uniswapV2Pair;
    uint256 internal priceDrop;
    uint64 internal averagePriceWindow;
    uint64 internal fraction;
    address internal token0;
    uint64 internal startupTimestamp;

    struct Observation {
        uint64 timestampLast;
        uint price0CumulativeLast;
        uint price1CumulativeLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    
    Observation public pairObservation;
    
    constructor() {
        startupTimestamp = currentBlockTimestamp();
        pairObservation.timestampLast = currentBlockTimestamp();
    }

    function maxAddLiquidity(
    ) 
        public 
        view 
        //      traded1 -> traded2
        returns(uint256, uint256) 
    {
// console.log("solidity:maxAddL:#1");
        (uint256 traded1, uint256 reserve1, /*uint32 blockTimestampLast*/) = _uniswapPrices();
// console.log("solidity:traded1 = ", traded1);
// console.log("solidity:reserve1 = ", reserve1);
// console.log("solidity:maxAddL:#2");
        
        // Math.sqrt(lowestPrice * traded1 * reserve1)
        // return  (
        //     priceAverage
        //         .muluq(FixedPoint.encode(uint112(FRACTION*100 - priceDrop)))
        //         .divuq(FixedPoint.encode(uint112(FRACTION*100)))
        //         .muluq(FixedPoint.encode(uint112(traded1)))
        //         .muluq(FixedPoint.encode(uint112(reserve1)))
        //     )
        //     .sqrt().decode();
console.log("solidity:PriceAverage0 = ", pairObservation.price0Average._x);
console.log("solidity:PriceAverage1 = ", pairObservation.price1Average._x);
        
//         // Note that (traded1 * reserve1) will overflow in uint112. so need to exlude from sqrt like this 
//         // Math.sqrt(lowestPrice * traded1 * reserve1) =  Math.sqrt(lowestPrice) * Math.sqrt(traded1) * Math.sqrt(reserve1)
// console.log("solidity:traded1 = ", traded1);
// console.log("solidity:X1 = ", FixedPoint.encode(uint112(reserve1))._x);
// console.log("solidity:X2 = ", FixedPoint.encode(uint112(FRACTION*100))._x);

        uint256 tradedNew = traded1;
        if (
            traded1 == 0 || 
            reserve1 == 0 || 
            pairObservation.price0Average._x == 0
        ) {
            
        } else {
            
// uint8 RESOLUTION = 112;
//     // uint256 public constant Q112 = 0x10000000000000000000000000000; // 2**112
//     // uint256 private constant Q224 = 0x100000000000000000000000000000000000000000000000000000000; // 2**224
//     uint256 LOWER_MASK = 0xffffffffffffffffffffffffffff; // decimal of UQ*x112 (lower 112 bits)

// uint112 upper_self = uint112(x >> RESOLUTION); // * 2^0
// uint112 lower_self = uint112(x & LOWER_MASK); // * 2^-112
// uint112 upper_other = uint112(y >> RESOLUTION); // * 2^0
// uint112 lower_other = uint112(y & LOWER_MASK); // * 2^-112

// console.log("upper_self = ", upper_self);
// console.log("lower_self = ", lower_self);
// console.log("upper_other = ", upper_other);
// console.log("lower_other = ", lower_other);


// // partial products
// uint224 upper = uint224(upper_self) * upper_other; // * 2^0
// uint224 lower = uint224(lower_self) * lower_other; // * 2^-224
// uint224 uppers_lowero = uint224(upper_self) * lower_other; // * 2^-112
// uint224 uppero_lowers = uint224(upper_other) * lower_self; // * 2^-112

// console.log("upper = ", upper);
// console.log("lower = ", lower);
// console.log("uppers_lowero = ", uppers_lowero);
// console.log("lower_other = ", lower_other);

// uint256 sum = uint256(upper << RESOLUTION) + uppers_lowero + uppero_lowers + (lower >> RESOLUTION);

// console.log("sum = ", sum);
            // tradedNew = (
            //     FixedPoint.encode(uint112(traded1)).sqrt()
            //     .muluq(
            //         (
            //             FixedPoint.encode(uint112(reserve1))
            //     //        .divuq(FixedPoint.encode(uint112(FRACTION*100)))
            //         ).sqrt()
            //     )
            //     .divuq(
            //         (
            //             pairObservation.price0Average
            //             .muluq(FixedPoint.encode(uint112(uint256(fraction)*100 - priceDrop)))
                        
            //         ).sqrt()
            //     )
            //     // .divuq(
            //     //     FixedPoint.encode(uint112(FRACTION*100)).sqrt()
            //     // )
            // ).decode()*1000;

FixedPoint.uq112x112 memory q1 = FixedPoint.encode(uint112(sqrt(traded1)));
FixedPoint.uq112x112 memory q2 = FixedPoint.encode(uint112(sqrt(reserve1)));
FixedPoint.uq112x112 memory q3 = (pairObservation.price0Average.muluq(FixedPoint.encode(uint112(uint256(fraction) - priceDrop)))).sqrt();
FixedPoint.uq112x112 memory q4 = FixedPoint.encode(uint112(1)).divuq(q3);

// console.log("==!q1==",q1._x);
// console.log("==!q2==",q2._x);
// console.log("==!q3==",q3._x);
// console.log("==!q4==",q4._x);

// FixedPoint.uq112x112 memory q5 = q2.muluq(q4);
// console.log("==!q5==",q5._x);
// FixedPoint.uq112x112 memory q6 = q1.muluq(q5);
// console.log("==!q6==",q6._x);

// tradedNew = q6.decode();
                    //traded1*reserve1/(priceaverage*pricedrop)

                    //traded1 * reserve1*(1/(priceaverage*pricedrop))
            tradedNew = 
            (
                q1
                .muluq(q2)
                .muluq(FixedPoint.encode(uint112(sqrt(fraction))))
                .muluq(
                    FixedPoint.encode(
                        uint112(1)
                    )
                    .divuq(q3)
                )
            ).decode();//*1000;
        }
        console.log("solidity:traded1 = ", traded1);
        console.log("solidity:traded2 = ", tradedNew);
//tradedNew = traded1;        
        return (traded1, tradedNew);
        
    }
    
    
    function _uniswapPrices(
    ) 
        internal 
        view 
        // reserveTraded, reserveReserved, blockTimestampLast
        returns(uint112, uint112, uint32)
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        require (reserve0 != 0 && reserve1 != 0, "RESERVES_EMPTY");
        if (IUniswapV2Pair(uniswapV2Pair).token0() == token0) {
            return (reserve0, reserve1, blockTimestampLast);
        } else {
            return (reserve1, reserve0, blockTimestampLast);
            
        }
        
    }


    function oracleInit(
        address uniswapV2Pair_,
        uint256 priceDrop_,
        uint64 averagePriceWindow_,
        uint64 fraction_
    ) 
        internal
    {
        uniswapV2Pair = uniswapV2Pair_;
        priceDrop = priceDrop_;
        averagePriceWindow = averagePriceWindow_;
        fraction = fraction_;
        token0 = IUniswapV2Pair(uniswapV2Pair).token0();
        token0 = token0 == address(this) ? token0 : IUniswapV2Pair(uniswapV2Pair).token1();
        
    }
    
    
    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**64 - 1]
    function currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp % 2 ** 64);
    }

    function update() internal {
        
        // if (pairObservation.timestampLast == 0) {
        //     console.log("!!!!!!!!!");
        //     console.log(IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast());
        //     //force sync
        //     IUniswapV2Pair(uniswapV2Pair).sync();
        //     console.log(IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast());
            
        // }


console.log("solidity:update()");
        uint64 blockTimestamp = currentBlockTimestamp();
        uint price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        uint price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
console.log("solidity:update():#2");
console.log("solidity:update():price0Cumulative = ", price0Cumulative);
console.log("solidity:update():price1Cumulative = ", price1Cumulative);

        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;

        // ensure that at least one full period has passed since the last update

        uint64 windowSize = (blockTimestamp - startupTimestamp)*averagePriceWindow/fraction;
console.log("solidity:update():timeElapsed = ", timeElapsed);
console.log("solidity:update():windowSize = ", windowSize);
        // require(timeElapsed >= windowSize, "PERIOD_NOT_ELAPSED");
        // require(price0Cumulative != 0 && price1Cumulative != 0, "CUMULATIVE_PRICE_IS_EMPTY");

        // special case
        // if price0Cumulative or price1Cumulative equal 0. we set current price reserve1/reserve2
        if (price0Cumulative == 0 || price1Cumulative == 0) {
console.log("solidity:update()######1");
            uint112 reserve1; uint112 reserve0; uint32 blockTimestampLast;
            (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
console.log("solidity:update()######2");
            if (reserve1 != 0 && reserve0 != 0) {

console.log("solidity:update()######3");
                // pairObservation.price0Average = FixedPoint.uq112x112(reserve1).divuq(FixedPoint.uq112x112(reserve0));
                // pairObservation.price1Average = FixedPoint.uq112x112(reserve0).divuq(FixedPoint.uq112x112(reserve1));
                pairObservation.price0Average = FixedPoint.encode(reserve1).divuq(FixedPoint.encode(reserve0));
                pairObservation.price1Average = FixedPoint.encode(reserve0).divuq(FixedPoint.encode(reserve1));

                pairObservation.price0CumulativeLast = pairObservation.price0Average._x;
                pairObservation.price1CumulativeLast = pairObservation.price1Average._x;
                
                pairObservation.timestampLast = blockTimestamp;
            }
        } else if (
            timeElapsed >= windowSize &&
            windowSize != 0
        ) {
            console.log("solidity:update()######- updated");
            console.log("solidity:update()######- updated price0Cumulative                      = ", price0Cumulative);
            console.log("solidity:update()######- updated pairObservation.price0CumulativeLast  = ", pairObservation.price0CumulativeLast);
            console.log("solidity:update()######- updated timeElapsed                           = ", timeElapsed);

            uint112 reserve1; uint112 reserve0; uint32 blockTimestampLast;
            (reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();

            // pairObservation.price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - pairObservation.price0CumulativeLast) / timeElapsed));
            // pairObservation.price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - pairObservation.price1CumulativeLast) / timeElapsed));

            FixedPoint.uq112x112 memory currentPrice0 = FixedPoint.encode(reserve1).divuq(FixedPoint.encode(reserve0));
            FixedPoint.uq112x112 memory currentPrice1 = FixedPoint.encode(reserve0).divuq(FixedPoint.encode(reserve1));

            pairObservation.price0Average = FixedPoint.uq112x112(uint224(currentPrice0._x - pairObservation.price0CumulativeLast)).divuq(FixedPoint.encode(timeElapsed));
            pairObservation.price1Average = FixedPoint.uq112x112(uint224(currentPrice1._x - pairObservation.price1CumulativeLast)).divuq(FixedPoint.encode(timeElapsed));
            
            pairObservation.price0CumulativeLast = price0Cumulative;
            pairObservation.price1CumulativeLast = price1Cumulative;
            console.log("solidity:update()######- updated price0Average                         = ", pairObservation.price0Average._x);
            console.log("solidity:update()######- updated price1Average                         = ", pairObservation.price1Average._x);

            pairObservation.timestampLast = blockTimestamp;
        }
        console.log("solidity:update(): is out of here ???");
    }

    function sqrt(
        uint256 x
    ) 
        internal 
        pure 
        returns(uint256 result) 
    {
        if (x == 0) {
            return 0;
        }
        // Calculate the square root of the perfect square of a
        // power of two that is the closest to x.
        uint256 xAux = uint256(x);
        result = 1;
        if (xAux >= 0x100000000000000000000000000000000) {
            xAux >>= 128;
            result <<= 64;
        }
        if (xAux >= 0x10000000000000000) {
            xAux >>= 64;
            result <<= 32;
        }
        if (xAux >= 0x100000000) {
            xAux >>= 32;
            result <<= 16;
        }
        if (xAux >= 0x10000) {
            xAux >>= 16;
            result <<= 8;
        }
        if (xAux >= 0x100) {
            xAux >>= 8;
            result <<= 4;
        }
        if (xAux >= 0x10) {
            xAux >>= 4;
            result <<= 2;
        }
        if (xAux >= 0x8) {
            result <<= 1;
        }
        // The operations can never overflow because the result is
        // max 2^127 when it enters this block.
        unchecked {
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1;
            result = (result + x / result) >> 1; // Seven iterations should be enough
            uint256 roundedDownResult = x / result;
            return result >= roundedDownResult ? roundedDownResult : result;
        }
    }
    
    
}