// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";

import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

//import "hardhat/console.sol";

//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";

import "./ITRv2.sol";

contract Main is Ownable, IERC777Recipient, IERC777Sender {
    using FixedPoint for *;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 internal constant OWNER_ROLE = 0x4f574e4552000000000000000000000000000000000000000000000000000000;
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
	uint256 internal constant FRACTION = 100000;
    
    address public immutable tradedToken;
    address public immutable reserveToken;
    uint256 public immutable priceDrop;
    uint256 public immutable minClaimPriceNum;
    uint256 public immutable minClaimPriceDen;
    /**
    * @custom:shortd uniswap v2 pair
    * @notice uniswap v2 pair
    */
    address internal uniswapV2Pair;
    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    IUniswapV2Router02 internal UniswapV2Router02;

    Observation[] internal pairObservation;

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
    

    uint256 internal totalCumulativeClaimed;
    
    uint8 private runOnlyOnceFlag;
    modifier runOnlyOnce() {
        require(runOnlyOnceFlag < 1, "already called");
        runOnlyOnceFlag = 1;
        _;
    }
    /**
    @param reserveToken_ reserve token address
    @param granularitySize_ the number of observations
    @param priceDrop_ price drop while add liquidity
    @param windowSize_ the desired amount of time over which the moving average should be computed
    @param lockupIntervalAmount_ interval amount in days (see minimum lib)
    @param minClaimPriceNum_ (numerator) minimum claim price that should be after "sell all claimed tokens".
    @param minClaimPriceDen_ (denominator) minimum claim price that should be after "sell all claimed tokens".
    */
    constructor(
        address reserveToken_, //” (USDC)
        uint8 granularitySize_,
        uint256 priceDrop_,
        uint256 windowSize_,
        uint64 lockupIntervalAmount_,
        uint256 minClaimPriceNum_,
        uint256 minClaimPriceDen_
        
    ) {
        require(granularitySize_ > 1, "granularitySize invalid");
        require(
            (periodSize = windowSize_ / granularitySize_) * granularitySize_ == windowSize_,
            "window not evenly divisible"
        );
        require(reserveToken_ != address(0), "reserveToken invalid");
        windowSize = windowSize_;
        granularitySize = granularitySize_;

        tradedToken = address(new ITRv2("Intercoin Investor Token", "ITR", lockupIntervalAmount_));
        reserveToken = reserveToken_;
        priceDrop = priceDrop_;
        minClaimPriceNum = minClaimPriceNum_;
        minClaimPriceDen = minClaimPriceDen_;
        
        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();
        UniswapV2Router02 = IUniswapV2Router02(uniswapRouter);

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        
        //create Pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);
        require(uniswapV2Pair != address(0), "can't create pair");

        fillEmptyObservations();

        //grant sender owner role
        ITRv2(tradedToken).grantRole(OWNER_ROLE, msg.sender);

    }

    // update the cumulative price for the observation at the current timestamp. each observation is updated at most
    // once per epoch period.
    function update() external {

        // get the observation for the current period
        uint8 observationIndex = observationIndexOf(block.timestamp);

        // we only want to commit updates once per period (i.e. windowSize / granularitySize)
        uint timeElapsed = block.timestamp - pairObservation[observationIndex].timestamp;

        Observation storage firstObservation = getFirstObservationInWindow();

        if (
            timeElapsed > periodSize ||
            firstObservation.timestamp == 0
        ) {
            
//console.log("update():success");
            (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = _uniswapPrices();

            (uint price0Cumulative, uint price1Cumulative,) = currentCumulativePrices(uniswapV2Pair, reserve0, reserve1, blockTimestampLast);
            pairObservation[observationIndex].timestamp = block.timestamp;
            pairObservation[observationIndex].price0Cumulative = price0Cumulative;
            pairObservation[observationIndex].price1Cumulative = price1Cumulative;

            if (firstObservation.timestamp == 0) {
                uint8 firstObservationIndex = (observationIndex + 1) % granularitySize;
                pairObservation[firstObservationIndex].timestamp = block.timestamp;
                pairObservation[firstObservationIndex].price0Cumulative = price0Cumulative;
                pairObservation[firstObservationIndex].price1Cumulative = price1Cumulative;
            }
        } else {
//console.log("update():passed");
        }
    }
    
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {
       
    }

    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {

    }


    ////////////////////////////////////////////////////////////////////////
    // public section //////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////
    /**
    * @dev adding initial liquidity. need to donate `amountReserveToken` of reserveToken into the contract. can be called once
    * @param amountTradedToken amount of traded token which will be claimed into contract and adding as liquidity
    * @param amountReserveToken amount of reserve token which must be donate into contract by user and adding as liquidity
    */
    function addInitialLiquidity(
        uint256 amountTradedToken,
        uint256 amountReserveToken
    ) 
        public 
        runOnlyOnce
    {

        require(amountReserveToken <= ERC777(reserveToken).balanceOf(address(this)), "reserveAmount is insufficient");
        _claim(amountTradedToken, address(this));

        ERC777(tradedToken).approve(uniswapRouter, amountTradedToken);
        ERC777(reserveToken).approve(uniswapRouter, amountReserveToken);

        (/* uint256 A*/, /*uint256 B*/, uint256 lpTokens) = UniswapV2Router02.addLiquidity(
            tradedToken,
            reserveToken,
            amountTradedToken,
            amountReserveToken,
            0, // there may be some slippage
            0, // there may be some slippage
            address(this),
            block.timestamp
        );
        // move lp tokens to dead address
        ERC777(uniswapV2Pair).transfer(deadAddress, lpTokens);

    }

    /**
    @dev   … mints to caller
    */
    function claim(
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        _validateClaim(tradedTokenAmount, msg.sender);
        _claim(tradedTokenAmount, msg.sender);
        
    }

    /**
    @dev   … mints to account
    */
    function claim(
        uint256 tradedTokenAmount,
        address account
    ) 
        public 
        onlyOwner
    {
        _validateClaim(tradedTokenAmount, account);
        _claim(tradedTokenAmount, account);
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

        require(tradedTokenAmount <= maxAddLiquidity(), "maxAddLiquidity exceeded");

        // claim to address(this)
        ITRv2(tradedToken).claim(address(this), tradedTokenAmount);
        // trade traed tokens and add liquidity
        uint256 lpTokens = _sellTradedAndLiquidity(tradedTokenAmount);
        // move lp tokens to dead address
        ERC777(uniswapV2Pair).transfer(deadAddress, lpTokens);
    }

    function maxAddLiquidity(
    ) 
        public 
        view 
        returns(uint256) 
    {

        (uint256 traded1, uint256 reserve1, uint32 blockTimestampLast) = _uniswapPrices();
        
        FixedPoint.uq112x112 memory priceAverage = getPriceAverage(traded1, reserve1, blockTimestampLast);
        // Math.sqrt(lowestPrice * traded1 * reserve1)
        // return  (
        //     priceAverage
        //         .muluq(FixedPoint.encode(uint112(FRACTION*100 - priceDrop)))
        //         .divuq(FixedPoint.encode(uint112(FRACTION*100)))
        //         .muluq(FixedPoint.encode(uint112(traded1)))
        //         .muluq(FixedPoint.encode(uint112(reserve1)))
        //     )
        //     .sqrt().decode();

        
        // Note that (traded1 * reserve1) will overflow in uint112. so need to exlude from sqrt like this 
        // Math.sqrt(lowestPrice * traded1 * reserve1) =  Math.sqrt(lowestPrice) * Math.sqrt(traded1) * Math.sqrt(reserve1)

        return traded1 - (
            
            FixedPoint.encode(uint112(traded1)).sqrt()
            .muluq(
                FixedPoint.encode(uint112(reserve1)).sqrt()
            )
            .muluq(
                (
                    priceAverage
                    .muluq(FixedPoint.encode(uint112(FRACTION*100 - priceDrop)))
                    .divuq(FixedPoint.encode(uint112(FRACTION*100)))
                ).sqrt()
            )
        ).decode();
        
    }
    
    function renounceOwnership(
    ) 
        public 
        virtual 
        override 
        onlyOwner 
    {
        transferOwnerRole(owner(), address(0));
        super.renounceOwnership();
    }
    
    function transferOwnership(
        address newOwner
    ) 
        public 
        virtual 
        override 
        onlyOwner 
    {
        transferOwnerRole(owner(), newOwner);
        super.transferOwnership(newOwner);
    }

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    function _validateClaim(
        uint256 tradedTokenAmount,
        address account
    ) 
        internal
    {
        // TODO



        // // simulate swap cumulativeClaim to reserve token and check price

        // // price should be less than minClaimPrice
        
        // (uint256 rTraded, /*uint256 rReserved*/, /*uint256 priceTraded*/) = _uniswapPrices();
        // require(totalCumulativeClaimed-tradedTokenAmount < rTraded);
        
    }

    function _claim(
        uint256 tradedTokenAmount,
        address account
    ) 
        internal
    {
        totalCumulativeClaimed += tradedTokenAmount;
        ITRv2(tradedToken).claim(account, tradedTokenAmount);
    }


    function transferOwnerRole(address from, address to) internal {
        //revoke owner role from older role
        ITRv2(tradedToken).revokeRole(OWNER_ROLE, from);

        //grant owner role to newOwner
        ITRv2(tradedToken).grantRole(OWNER_ROLE, to);
    }

    function getPriceAverage(
        uint256 traded1, 
        uint256 reserve1, 
        uint32 blockTimestampLast
    ) 
        internal 
        view 
        returns (FixedPoint.uq112x112 memory) 
    {
        Observation storage firstObservation = getFirstObservationInWindow();

        uint timeElapsed = block.timestamp - firstObservation.timestamp;

        // console.log("getPriceAverage:firstObservation.timestamp=",firstObservation.timestamp);
        // console.log("getPriceAverage:block.timestamp=",block.timestamp);
        // console.log("getPriceAverage:windowSize=",windowSize);
        // console.log("getPriceAverage:timeElapsed=",timeElapsed);
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

        return priceAverage;

    }


/*
    function expectedAmount(
        address tokenFrom,
        uint256 amount0,
        address[][] memory swapPaths,
        address forceTokenSwap,
        uint256 subReserveFrom,
        uint256 subReserveTo
    )
        internal
        view
        returns(
            address,
            uint256
        )
    {

        if (forceTokenSwap == address(0)) {

            address tokenFromTmp;
            uint256 amount0Tmp;
        
            for(uint256 i = 0; i < swapPaths.length; i++) {
                if (tokenFrom == swapPaths[i][swapPaths[i].length-1]) { // if tokenFrom is already destination token
                    return (tokenFrom, amount0);
                }

                tokenFromTmp = tokenFrom;
                amount0Tmp = amount0;
                
                for(uint256 j = 0; j < swapPaths[i].length; j++) {
                
                    (bool success, uint256 amountOut) = _swap(tokenFromTmp, swapPaths[i][j], amount0Tmp, subReserveFrom, subReserveTo);
                    if (success) {
                        //ret = amountOut;
                    } else {
                        break;
                    }

                    // if swap didn't brake before last iteration then we think that swap is done
                    if (j == swapPaths[i].length-1) { 
                        return (swapPaths[i][j], amountOut);
                    } else {
                        tokenFromTmp = swapPaths[i][j];
                        amount0Tmp = amountOut;
                    }
                }
            }
            revert("paths invalid");
        } else {
            (bool success, uint256 amountOut) = _swap(tokenFrom, forceTokenSwap, amount0, subReserveFrom, subReserveTo);
            if (success) {
                return (forceTokenSwap, amountOut);
            }
            revert("force swap invalid");
        }
    }

    function _swap(
        address tokenFrom,
        address tokenTo,
        uint256 amountFrom,
        uint256 subReserveFrom,
        uint256 subReserveTo
    )
        internal
        view 
        returns (
            bool success,
            uint256 ret
            //address pair
        )
    {
        success = false;
        address pair = IUniswapV2Factory(uniswapRouterFactory).getPair(tokenFrom, tokenTo);
        
        if (pair == address(0)) {
            //break;
            //revert("pair == address(0)");
        } else {

            (uint112 _reserve0, uint112 _reserve1,) = IUniswapV2Pair(pair).getReserves();

            if (_reserve0 == 0 || _reserve1 == 0) {
                //break;
            } else {
                
                (_reserve0, _reserve1) = (tokenFrom == IUniswapV2Pair(pair).token0()) ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
                if (subReserveFrom >= _reserve0 || subReserveTo >= _reserve1) {
                    //break;
                } else {
                    _reserve0 -= uint112(subReserveFrom);
                    _reserve1 -= uint112(subReserveTo);
                                                                            // amountin reservein reserveout
                    ret = IUniswapV2Router02(uniswapRouter).getAmountOut(amountFrom, _reserve0, _reserve1);

                    if (ret != 0) {
                        success = true;
                    }
                }
            }
        }
    }
*/
    function _sellTradedAndLiquidity(
        uint256 incomingTradedToken
    )
        internal
        returns(uint256)
    {

        (uint256 rTraded, /*uint256 rReserved*/, /*uint256 priceTraded*/) = _uniswapPrices();

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

        return lpTokens;
        
        

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
    function observationIndexOf(uint timestamp) internal view returns (uint8 index) {
        uint epochPeriod = timestamp / periodSize;
        return uint8(epochPeriod % granularitySize);
    }

    // returns the observation from the oldest epoch (at the beginning of the window) relative to the current time
    function getFirstObservationInWindow() internal view returns (Observation storage firstObservation) {
        uint8 observationIndex = observationIndexOf(block.timestamp);
// console.log("getFirstObservationInWindow:observationIndex = ", observationIndex);
        // no overflow issue. if observationIndex + 1 overflows, result is still zero.
        uint8 firstObservationIndex = (observationIndex + 1) % granularitySize;
        
// console.log("getFirstObservationInWindow:firstObservationIndex = ", firstObservationIndex);
        firstObservation = pairObservation[firstObservationIndex];
// console.log("getFirstObservationInWindow:firstObservation.timestamp = ", firstObservation.timestamp);
    }


}