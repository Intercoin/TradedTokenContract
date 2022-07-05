// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "hardhat/console.sol";

//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";

import "./ITRv2.sol";

contract Main is Ownable {
    using FixedPoint for *;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;

	uint256 internal constant FRACTION = 100000;
    
    address public immutable tradedToken;
    address public immutable reserveToken;
    uint256 public immutable priceDrop;
    /**
    * @custom:shortd uniswap v2 pair
    * @notice uniswap v2 pair
    */
    address internal uniswapV2Pair;
    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    IUniswapV2Router02 internal UniswapV2Router02;

    Observation[] pairObservation;

    // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    uint public immutable windowSize;
    // the number of observations stored for pair, i.e. how many price observations are stored for the window.
    // as granularitySize increases from 1, more frequent updates are needed, but moving averages become more precise.
    // averages are computed over intervals with sizes in the range:
    //   [windowSize - (windowSize / granularitySize) * 2, windowSize]
    // e.g. if the window size is 24 hours, and the granularitySize is 24, the oracle will return the average price for
    //   the period:
    //   [now - [22 hours, 24 hours], now]
    uint8 public immutable granularitySize;
    // this is redundant with granularitySize and windowSize, but stored for gas savings & informational purposes.
    uint public immutable periodSize;

    constructor(
        address reserveToken_, //” (USDC)
        uint8 granularitySize_,
        uint256 priceDrop_,
        uint256 windowSize_
    ) {
        require(granularitySize_ > 1, "granularitySize invalid");
        require(
            (periodSize = windowSize_ / granularitySize_) * granularitySize_ == windowSize_,
            "window not evenly divisible"
        );
        require(reserveToken_ != address(0), "reserveToken invalid");
        windowSize = windowSize_;
        granularitySize = granularitySize_;

        tradedToken = address(new ITRv2("Intercoin Investor Token", "ITR"));
        reserveToken = reserveToken_;
        priceDrop = priceDrop_;
        
        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();
        UniswapV2Router02 = IUniswapV2Router02(uniswapRouter);

        
    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update() external {
        actualizePairAddress();
        fillEmptyObservations();
        
        // get the observation for the current period
        uint8 observationIndex = observationIndexOf(block.timestamp);

        // we only want to commit updates once per period (i.e. windowSize / granularitySize)
        uint timeElapsed = block.timestamp - pairObservation[claimobservationIndex].timestamp;
        if (timeElapsed > periodSize) {

            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = _uniswapPrices();

            (uint price0Cumulative, uint price1Cumulative,) = currentCumulativePrices(uniswapV2Pair, reserve0, reserve1, blockTimestampLast);
            pairObservation[observationIndex].timestamp = block.timestamp;
            pairObservation[observationIndex].price0Cumulative = price0Cumulative;
            pairObservation[observationIndex].price1Cumulative = price1Cumulative;
        }
    }

    ////////////////////////////////////////////////////////////////////////
    // public section //////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    /**
    @dev   … mints to caller
    */
    function claim(
        
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        ITRv2(tradedToken).claim(msg.sender, tradedTokenAmount);
    }


    /**
    @dev  … mints, sells, adds liquidity, sends LP to 0x0
    */
    function addLiquidity(
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        actualizePairAddress();
        fillEmptyObservations();
        
        (uint256 traded1, /*uint256 reserve1*/, /*uint256 priceTraded*/, /*uint256 priceReserved*/, /*uint32 blockTimestampLast*/) = uniswapPrices();

        uint256 traded2 = getTraded2();
        uint256 maxAddLiquidity = traded1 - traded2;
        

        require(tradedTokenAmount <= maxAddLiquidity, "maxAddLiquidity exceeded");

        // claim to address(this)
        ITRv2(tradedToken).claim(tradedTokenAmount);
        _sellTradedAndStake(tradedTokenAmount);
    }


    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    function getTraded2() internal view returns(uint256) {
        (uint256 traded1, uint256 reserve1, /*uint256 priceTraded*/, /*uint256 priceReserved*/, uint32 blockTimestampLast) = uniswapPrices();
        
        Observation storage firstObservation = getFirstObservationInWindow();

        uint timeElapsed = block.timestamp - firstObservation.timestamp;
        require(timeElapsed <= windowSize, "MISSING_HISTORICAL_OBSERVATION");
        // should never happen.
        require(timeElapsed >= windowSize - periodSize * 2, "SlidingWindowOracle: UNEXPECTED_TIME_ELAPSED");

        (uint price0Cumulative, uint price1Cumulative,) = currentCumulativePrices(uniswapV2Pair, uint112(traded1), uint112(reserve1), blockTimestampLast);
        
        FixedPoint.uq112x112 memory priceAverage;

        if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
            priceAverage = FixedPoint.uq112x112(
                uint224((price0Cumulative - firstObservation.price0Cumulative) / timeElapsed)
            );

        } else {
            priceAverage = FixedPoint.uq112x112(
                uint224((price1Cumulative - firstObservation.price1Cumulative) / timeElapsed)
            );
        }


        return  (
            priceAverage
                .muluq(FixedPoint.encode(uint112(FRACTION - priceDrop)))
                .divuq(FixedPoint.encode(uint112(FRACTION)))
                .divuq(FixedPoint.encode(uint112(traded1)))
                .divuq(FixedPoint.encode(uint112(reserve1)))
            )
            .sqrt().decode();
        //return sqrt(price2 / traded1 / reserve1);
    }

     function _sellTradedAndStake(
        uint256 incomingTradedToken
    )
        internal
    {

        (uint256 rTraded, /*uint256 rReserved*/, /*uint256 priceTraded*/, /*uint256 priceReserved*/, /*uint32 blockTimestampLast*/) = uniswapPrices();
        

        uint256 r3 = 
            sqrt(
                (rTraded + incomingTradedToken)*(rTraded)
            ) - rTraded; //    
        require(r3 > 0 && incomingTradedToken > r3, "BAD_AMOUNT");
        // remaining (r2-r3) we will exchange at uniswap to traded token
        uint256 amountReserveToken = doSwapOnUniswap(tradedToken, reserveToken, r3);
        uint256 amountTradedToken = incomingTradedToken - r3;

        
        require(
            ERC777(tradedToken).approve(uniswapRouter, amountTradedToken)
            && ERC777(reserveToken).approve(uniswapRouter, amountReserveToken),
            "APPROVE_FAILED"
        );


        (/*uint256 A*/, /*uint256 B*/, uint256 lpTokens) = UniswapV2Router02.addLiquidity(
            tradedToken,
            reserveToken,
            amountTradedToken,
            amountReserveToken,
            0, // there may be some slippage
            0, // there may be some slippage
            address(this),
            block.timestamp
        );
        require (lpTokens > 0, "NO_LIQUIDITY");

        ERC777(uniswapV2Pair).transfer(deadAddress, lpTokens);
        

    }

    function doSwapOnUniswap(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn
    ) 
        internal 
        returns(uint256 amountOut) 
    {
        if (tokenIn == tokenOut) {
            // situation when WETH is a reserve token
            amountOut = amountIn;
        } else {
            require(ERC777(tokenIn).approve(address(uniswapRouter), amountIn), "APPROVE_FAILED");
            address[] memory path = new address[](2);
            path[0] = address(tokenIn);
            path[1] = address(tokenOut);
            // amountOutMin is set to 0, so only do this with pairs that have deep liquidity
            uint256[] memory outputAmounts = UniswapV2Router02.swapExactTokensForTokens(
                amountIn, 0, path, address(this), block.timestamp
            );
            amountOut = outputAmounts[1];
        }
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


    
    function actualizePairAddress() internal {
        if (uniswapV2Pair == address(0)) { //only for first call
            uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).getPair(tradedToken, reserveToken);
        }
        require(uniswapV2Pair != address(0), "can't find pair");

    }

    function fillEmptyObservations() internal {

            // populate the array with empty observations (first call only)
            for (uint i = pairObservation.length; i < granularitySize; i++) {
                pairObservation.push();
            }

    }

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair,
        uint112 reserve0, 
        uint112 reserve1, 
        uint32 blockTimestampLast
    ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        //(uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = _uniswapPrices();

        if (blockTimestampLast != blockTimestamp) {
            // subtraction overflow is desired
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            // addition overflow is desired
            // counterfactual
            price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
            // counterfactual
            price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
        }
    }

    function uniswapPrices(
    ) 
        internal 
        view 
        // reserveTraded, reserveReserved, priceTraded, priceReserved, blockTimestamp
        returns(uint256, uint256, uint256, uint256, uint32)
    {
        (uint256 reserve0, uint256 reserve1, uint32 blockTimestamp) = _uniswapPrices();

        if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
            return(
                reserve0, 
                reserve1, 
                FRACTION * reserve0 / reserve1,
                FRACTION * reserve1 / reserve0,
                blockTimestamp
            );
        } else {
            return(
                reserve1, 
                reserve0, 
                FRACTION * reserve1 / reserve0,
                FRACTION * reserve0 / reserve1,
                blockTimestamp
            );
        }

    }

    function _uniswapPrices(
    ) 
        internal 
        view 
        // reserveTraded, reserveReserved, priceTraded, priceReserved
        returns(uint112, uint112, uint32)
    {

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();

        require (reserve0 != 0 && reserve1 != 0, "RESERVES_EMPTY");
        return (reserve0, reserve1, blockTimestampLast);
    }

    // returns the index of the observation corresponding to the given timestamp
    function observationIndexOf(uint timestamp) public view returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularitySize);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow() private view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint8 firstObservationIndex = (observationIndex + 1) % granularitySize;
        firstObservation = pairObservation[firstObservationIndex];
    }


}