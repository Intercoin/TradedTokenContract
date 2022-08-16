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
import "./ExecuteManager.sol";

contract Main is Ownable, IERC777Recipient, IERC777Sender, ExecuteManager {
    using FixedPoint for *;

    
    struct PriceNumDen{
        uint256 numerator;
        uint256 denominator;
    }

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    bytes32 internal constant OWNER_ROLE = 0x4f574e4552000000000000000000000000000000000000000000000000000000;
    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint64 internal constant averagePriceWindow = 5;
	uint64 internal constant FRACTION = 10000;
    
    address public immutable tradedToken;
    address public immutable reserveToken;
    uint256 public immutable priceDrop;
    
    PriceNumDen minClaimPrice;
    address externalToken;
    PriceNumDen externalTokenExchangePrice;

    
    /**
    * @custom:shortd uniswap v2 pair
    * @notice uniswap v2 pair
    */
    address public uniswapV2Pair;
    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    IUniswapV2Router02 internal UniswapV2Router02;

    // keep gas when try to get reserves
    // if token01 == true then (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) so reserve0 it's reserves of TradedToken
    bool internal immutable token01; 
    

    uint64 internal startupTimestamp;

    bool alreadyRunStartupSync;
    struct Observation {
        uint64 timestampLast;
        uint price0CumulativeLast;
        uint price1CumulativeLast;
        FixedPoint.uq112x112 price0Average;
        FixedPoint.uq112x112 price1Average;
    }

    
    Observation public pairObservation;
  

    /**
    @param reserveToken_ reserve token address
    @param priceDrop_ price drop while add liquidity
    @param lockupIntervalAmount_ interval amount in days (see minimum lib)
    @param minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
    @param externalToken_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
    @param externalTokenExchangePrice_ (numerator,denominator) exchange price. used when user trying to excha external token to Traded
    */
    constructor(
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupIntervalAmount_,
        PriceNumDen memory minClaimPrice_,
        address externalToken_,
        PriceNumDen memory externalTokenExchangePrice_
    ) {
        
        require(reserveToken_ != address(0), "reserveToken invalid");
        

        tradedToken = address(new ITRv2("Intercoin Investor Token", "ITR", lockupIntervalAmount_));
        reserveToken = reserveToken_;
        priceDrop = priceDrop_;

        minClaimPrice.numerator = minClaimPrice_.numerator;
        minClaimPrice.denominator = minClaimPrice_.denominator;
        externalToken = externalToken_;
        externalTokenExchangePrice.numerator = externalTokenExchangePrice_.numerator;
        externalTokenExchangePrice.denominator = externalTokenExchangePrice_.denominator;
        
        
        // setup swap addresses
        (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();
        UniswapV2Router02 = IUniswapV2Router02(uniswapRouter);

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        
        //create Pair
        uniswapV2Pair = IUniswapV2Factory(uniswapRouterFactory).createPair(tradedToken, reserveToken);
        require(uniswapV2Pair != address(0), "can't create pair");

        //grant sender owner role
        ITRv2(tradedToken).grantRole(OWNER_ROLE, msg.sender);

        // oracleInit(
        //     uniswapV2Pair,
        //     priceDrop,
        //     averagePriceWindow,
        //     FRACTION
        // );

        startupTimestamp = currentBlockTimestamp();
        pairObservation.timestampLast = currentBlockTimestamp();

        // TypeError: Cannot write to immutable here: Immutable variables cannot be initialized inside an if statement.
        // if (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) {
        //     token01 = true;
        // }
        // but can do if use ternary operator :)
        token01 = (IUniswapV2Pair(uniswapV2Pair).token0() == tradedToken) ? true : false;

        IUniswapV2Pair(uniswapV2Pair).sync();


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

        // console.log("force sync start");

// //force sync
        //IUniswapV2Pair(uniswapV2Pair).sync();
        
        // // and update
        // update();


    }

    function forceSync() public {
         IUniswapV2Pair(uniswapV2Pair).sync();
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
        _validateClaim(tradedTokenAmount);
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
        onlyOwner // or redeemer ?
    {
        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account);
    }

    function claimViaExternal(
        uint256 externalTokenAmount,
        address account
    ) 
        public 
    {
        require(externalToken != address(0), "externalToken is not set");
        require(externalTokenAmount <= ERC777(externalToken).allowance(msg.sender, address(this)), "insufficient amount in allowance");

        ERC777(externalToken).transferFrom(msg.sender, deadAddress, externalTokenAmount);

        uint256 tradedTokenAmount = externalTokenAmount * externalTokenExchangePrice.numerator / externalTokenExchangePrice.denominator;

        _validateClaim(tradedTokenAmount);
        _claim(tradedTokenAmount, account);
    }
    // need to run immedialety after adding liquidity tx and sync cumulativePrice. BUT i's can't applicable if do in the same trasaction with addInitialLiquidity.
    // reserve0 and reserve1 still zero and 
    function singlePairSync() internal {
        if (alreadyRunStartupSync == false) {
            alreadyRunStartupSync = true;
            IUniswapV2Pair(uniswapV2Pair).sync();
        }
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
        singlePairSync();

        uint256 tradedReserve1;
        uint256 tradedReserve2;
        (tradedReserve1, tradedReserve2) = maxAddLiquidity();
        // console.log("ITRv2(tradedToken).maxAddLiquidity()");
        // console.log(tradedReserve1);
        // console.log(tradedReserve2);
        // console.log("---------------------------------");
        require(
            tradedReserve1 < tradedReserve2 && tradedTokenAmount <= (tradedReserve2 - tradedReserve1), 
            "maxAddLiquidity exceeded"
        );

        // claim to address(this)
        ITRv2(tradedToken).claim(address(this), tradedTokenAmount);
        // trade trade tokens and add liquidity
        uint256 lpTokens = _sellTradedAndLiquidity(tradedTokenAmount);
        // move lp tokens to dead address
        ERC777(uniswapV2Pair).transfer(deadAddress, lpTokens);

        update();
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

    
    function maxAddLiquidity(
    ) 
        public 
        view 
        //      traded1 -> traded2
        returns(uint256, uint256) 
    {
        // tradedNew = Math.sqrt(@tokenPair.r0 * @tokenPair.r1 / (average_price*(1-@price_drop)))

        uint112 reserve0;
        uint112 reserve1;
        uint32 blockTimestampLast;

        (reserve0, reserve1, blockTimestampLast) = _uniswapReserves();
        //(reserve0, reserve1, blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();

        FixedPoint.uq112x112 memory priceAverageData = getTradedAveragePrice();
console.log(6);
console.log("priceAverageData=",priceAverageData._x);
        FixedPoint.uq112x112 memory q1 = FixedPoint.encode(uint112(sqrt(reserve0)));
        FixedPoint.uq112x112 memory q2 = FixedPoint.encode(uint112(sqrt(reserve1)));
        FixedPoint.uq112x112 memory q3 = (priceAverageData.muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)))).sqrt();
        FixedPoint.uq112x112 memory q4 = FixedPoint.encode(uint112(1)).divuq(q3);

                    //traded1*reserve1/(priceaverage*pricedrop)

                    //traded1 * reserve1*(1/(priceaverage*pricedrop))

        uint256 reserve0New = 
        (
            q1
            .muluq(q2)
            .muluq(FixedPoint.encode(uint112(sqrt(FRACTION))))
            .muluq(
                FixedPoint.encode(
                    uint112(1)
                )
                .divuq(q3)
            )
        ).decode();
        
        console.log("solidity:traded1 = ", reserve0);
        console.log("solidity:traded2 = ", reserve0New);

        return (reserve0, reserve0New);
        
    }
    
    
    
    

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**64 - 1]
    function currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp % 2 ** 64);
    }

    function _uniswapReserves(
    ) 
        internal 
        view 
        // reserveTraded, reserveReserved, blockTimestampLast
        returns(uint112, uint112, uint32)
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        require (reserve0 != 0 && reserve1 != 0, "RESERVES_EMPTY");

        if (token01) {
            return (reserve0, reserve1, blockTimestampLast);
        } else {
            return (reserve1, reserve0, blockTimestampLast);
            
        }
        
    }


    function _validateClaim(
        uint256 tradedTokenAmount
    ) 
        internal
        view
    {
        // simulate swap totalCumulativeClaimed to reserve token and check price
        // price should be less than minClaimPrice

        (uint112 _reserve0, uint112 _reserve1,) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        uint256 totalCumulativeClaimed = ITRv2(tradedToken).totalCumulativeClaimed();
                                                // amountin reservein reserveout
        uint256 amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(totalCumulativeClaimed+tradedTokenAmount, _reserve0, _reserve1);
// console.log("totalCumulativeClaimed = ",totalCumulativeClaimed);
// console.log("tradedTokenAmount = ",tradedTokenAmount);
// console.log("_reserve0 = ",_reserve0);
// console.log("_reserve1 = ",_reserve1);
// console.log("amountOut = ",amountOut);

// console.log("price before   = ",uint256(FixedPoint.fraction(
//                 _reserve1,
//                 _reserve0
//             )._x));

// console.log("price after    = ",uint256(FixedPoint.fraction(
//                 _reserve1-amountOut,
//                 _reserve0+totalCumulativeClaimed+tradedTokenAmount
//             )._x));

// console.log("min claim      = ",uint256(FixedPoint.fraction(
//                 minClaimPrice.numerator,
//                 minClaimPrice.denominator
//             )._x));

        require (amountOut > 0, "errors in claim validation");
        
        require(
            FixedPoint.fraction(
                _reserve1-amountOut,
                _reserve0+totalCumulativeClaimed+tradedTokenAmount
            )._x
            > 
            FixedPoint.fraction(
                minClaimPrice.numerator,
                minClaimPrice.denominator
            )._x,
            "price after claim is lower than minClaimPrice"
        );
    }

    function _claim(
        uint256 tradedTokenAmount,
        address account
    ) 
        internal
    {
        //totalCumulativeClaimed += tradedTokenAmount;
        ITRv2(tradedToken).claim(account, tradedTokenAmount);
    }


    function transferOwnerRole(address from, address to) internal {
        //revoke owner role from older role
        ITRv2(tradedToken).revokeRole(OWNER_ROLE, from);

        //grant owner role to newOwner
        ITRv2(tradedToken).grantRole(OWNER_ROLE, to);
    }


    function _sellTradedAndLiquidity(
        uint256 incomingTradedToken
    )
        internal
        returns(uint256)
    {

        (uint256 rTraded, /*uint256 rReserved*/, /*uint256 priceTraded*/) = _uniswapReserves();

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

    
    function getTradedAveragePrice(
    ) 
        internal 
        view
        returns(FixedPoint.uq112x112 memory)
    {

        uint64 blockTimestamp = currentBlockTimestamp();
        console.log("1");
        uint price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        //uint price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
console.log("2");
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
console.log("3");
        uint64 windowSize = (blockTimestamp - startupTimestamp)*averagePriceWindow/FRACTION;
console.log("4");
        if (timeElapsed > windowSize && timeElapsed>0) {
            console.log("5");
            console.log("price0Cumulative                       =", price0Cumulative);
            console.log("pairObservation.price0CumulativeLast   =", pairObservation.price0CumulativeLast);
            console.log("timeElapsed                            =", timeElapsed);
            return FixedPoint.uq112x112(
                uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed)
            );
        } else {
            //use stored
            return pairObservation.price0Average;
        }

        // tradedAveragePrice = FixedPoint.uq112x112(
        //     uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed)
        // );

    }
    // divide a UQ112x112 by a uint112, returning a UQ112x112
    function uqdiv(uint224 x, uint112 y) internal pure returns (uint224 z) {
        z = x / uint224(y);
    }


    function update() internal {
        uint64 blockTimestamp = currentBlockTimestamp();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
        
        
        uint256 price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();

        pairObservation.price0Average = FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast)).divuq(FixedPoint.encode(timeElapsed));
        pairObservation.price0CumulativeLast = price0Cumulative;

        pairObservation.timestampLast = blockTimestamp;

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


    // // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    // function currentCumulativePrices(
    //     address pair,
    //     uint112 reserve0, 
    //     uint112 reserve1, 
    //     uint32 blockTimestampLast
    // ) internal view returns (uint price0Cumulative, uint price1Cumulative, uint32 blockTimestamp) {
    //     blockTimestamp = currentBlockTimestamp();
    //     price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
    //     price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

    //     // if time has elapsed since the last update on the pair, mock the accumulated price values
    //     //(uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = _uniswapReserves();

    //     if (blockTimestampLast != blockTimestamp) {
    //         // subtraction overflow is desired
    //         uint32 timeElapsed = blockTimestamp - blockTimestampLast;
    //         // addition overflow is desired
    //         // counterfactual
    //         price0Cumulative += uint(FixedPoint.fraction(reserve1, reserve0)._x) * timeElapsed;
    //         // counterfactual
    //         price1Cumulative += uint(FixedPoint.fraction(reserve0, reserve1)._x) * timeElapsed;
    //     }
    // }

}