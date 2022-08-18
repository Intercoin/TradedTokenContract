// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";

import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "hardhat/console.sol";

//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";

//import "./TradedToken.sol";
import "./ExecuteManager.sol";

import "./Liquidity.sol";

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

import "./minimums/libs/MinimumsLib.sol";




contract Main is Ownable, IERC777Recipient, IERC777Sender, ERC777, ExecuteManager {
    using FixedPoint for *;
    using MinimumsLib for MinimumsLib.UserStruct;
    
    struct PriceNumDen{
        uint256 numerator;
        uint256 denominator;
    }

    
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

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

    Liquidity internal internalLiquidity;
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
  

    // TODO 0:  remove AccesssControl   leave just Ownable interface
    uint256 immutable buyTaxMax;
    uint256 immutable sellTaxMax;

    uint64 internal constant LOCKUP_INTERVAL = 24*60*60; // day in seconds

    uint64 internal lockupIntervalAmount;
	
    uint256 public totalCumulativeClaimed;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    uint256 buyTax;
    uint256 sellTax;



    /**
    @param tokenName_ tokenName_
    @param tokenSymbol_ tokenSymbol_
    @param reserveToken_ reserve token address
    @param priceDrop_ price drop while add liquidity
    @param lockupIntervalAmount_ interval amount in days (see minimum lib)
    @param minClaimPrice_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
    @param externalToken_ (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
    @param externalTokenExchangePrice_ (numerator,denominator) exchange price. used when user trying to excha external token to Traded
    @param buyTaxMax_ buyTaxMax_
    @param sellTaxMax_ sellTaxMax_
    */
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupIntervalAmount_,
        PriceNumDen memory minClaimPrice_,
        address externalToken_,
        PriceNumDen memory externalTokenExchangePrice_,
        uint256 buyTaxMax_,
        uint256 sellTaxMax_
    ) 
        ERC777(tokenName_, tokenSymbol_, new address[](0))
    {
        
        buyTaxMax = buyTaxMax_;
        sellTaxMax = sellTaxMax_;


        require(reserveToken_ != address(0), "reserveToken invalid");
        
        tradedToken = address(this);


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

        // IUniswapV2Pair(uniswapV2Pair).sync(); !!!! not created yet

        internalLiquidity = new Liquidity(tradedToken, reserveToken_, uniswapRouter);

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

    function setBuyTax(
        uint256 fraction
    )
        onlyOwner
        public
    {
        buyTax = fraction;
    }

    function setSellTax(
        uint256 fraction
    )
        onlyOwner
        public
    {
        sellTax = fraction;
    }

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
            address(0), //address(this),
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
            //IUniswapV2Pair(uniswapV2Pair).sync();
            //console.log("singlePairSync - synced");
        } else {
            //console.log("singlePairSync - ALREADY synced");
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
        // console.log("TradedToken(tradedToken).maxAddLiquidity()");
        // console.log("solidity::addLiquidity::tradedReserve1 =",tradedReserve1);
        // console.log("solidity::addLiquidity::tradedReserve2 =",tradedReserve2);
        // console.log("---------------------------------");
        require(
            tradedReserve1 < tradedReserve2 && tradedTokenAmount <= (tradedReserve2 - tradedReserve1), 
            "maxAddLiquidity exceeded"
        );

        //if zero we've try to use max as possible of available tokens
        if (tradedTokenAmount == 0) {
            tradedTokenAmount = tradedReserve2 - tradedReserve1;
        }

       
        // trade trade tokens and add liquidity
        _sellTradedAndLiquidity(tradedTokenAmount);
        
        update();
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
// console.log("solidity::maxAddLiquidity::reserve0 =",reserve0);
// console.log("solidity::maxAddLiquidity::reserve1 =",reserve1);
        FixedPoint.uq112x112 memory priceAverageData = getTradedAveragePrice();
// console.log(6);
// console.log("priceAverageData=",priceAverageData._x);
        FixedPoint.uq112x112 memory q1 = FixedPoint.encode(uint112(sqrt(reserve0)));
        FixedPoint.uq112x112 memory q2 = FixedPoint.encode(uint112(sqrt(reserve1)));
        FixedPoint.uq112x112 memory q3 = (priceAverageData.muluq(FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)))).sqrt();
// console.log("q3=",q3._x);
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
        
        // console.log("solidity:traded1 = ", reserve0);
        // console.log("solidity:traded2 = ", reserve0New);

        return (reserve0, reserve0New);
        
    }
    
    
    
    

    ////////////////////////////////////////////////////////////////////////
    // internal section ////////////////////////////////////////////////////
    ////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address /*operator*/,
        address from,
        address to,
        uint256 amount
    ) 
        internal 
        virtual 
        override 
    {

        // owner - contract main
        // real owner User
        // console.log("======================");
        // console.log("                                   address               [isAdmin] [isOwner]");
        // console.log("operator       = ", operator, hasRole(DEFAULT_ADMIN_ROLE,operator), hasRole(CLAIM_ROLE,operator));
        // console.log("from           = ", from, hasRole(DEFAULT_ADMIN_ROLE,from), hasRole(CLAIM_ROLE,from));
        // console.log("to             = ", to, hasRole(DEFAULT_ADMIN_ROLE,to), hasRole(CLAIM_ROLE,to));
        // console.log("----------------------");
        // console.log("address(this)  = ", address(this), hasRole(DEFAULT_ADMIN_ROLE,address(this)), hasRole(CLAIM_ROLE,address(this)));
        // console.log("owner()        = ", owner(), hasRole(DEFAULT_ADMIN_ROLE,owner()), hasRole(CLAIM_ROLE,owner()));
        // console.log("uniswapRouter  = ", uniswapRouter, hasRole(DEFAULT_ADMIN_ROLE,uniswapRouter), hasRole(CLAIM_ROLE,uniswapRouter));

        if (
            // if minted
            (from == address(0)) ||
            // or burnt itself
            (from == address(this) && to == address(0))// ||
        ) {
            //skip validation
        } else {

            uint256 balance = balanceOf(from);
            uint256 locked = tokensLocked[from]._getMinimum();
            // console.log("balance = ",balance);
            // console.log("locked  = ",locked);
            // console.log("amount  = ",amount);
            require(balance - locked >= amount, "insufficient amount");
        }


    }    

    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual override {

        
        if (uniswapV2Pair == from) {
            amount -= amount*buyTax/FRACTION;
            _burn(from, amount*buyTax/FRACTION, "", "");
        }
        if (uniswapV2Pair == to) {
            amount -= amount*sellTax/FRACTION;
            _burn(to, amount*sellTax/FRACTION, "", "");
        }
        
        super._send(from, to, amount, userData, operatorData, requireReceptionAck);

        // require(from != address(0), "ERC777: transfer from the zero address");
        // require(to != address(0), "ERC777: transfer to the zero address");

        // address operator = _msgSender();

        // _callTokensToSend(operator, from, to, amount, userData, operatorData);

        // _move(operator, from, to, amount, userData, operatorData);

        // _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }


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
        uint256 totalCumulativeClaimed = totalCumulativeClaimed;
                                                // amountin reservein reserveout
        uint256 amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(totalCumulativeClaimed+tradedTokenAmount, _reserve0, _reserve1);

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
        totalCumulativeClaimed += tradedTokenAmount;

        _mint(account, tradedTokenAmount, "", "");
        if (
            _msgSender() != owner() && 
            _msgSender() != address(this)
        ) {    
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupIntervalAmount, LOCKUP_INTERVAL, true);
        }
        
    }

    function _sellTradedAndLiquidity(
        uint256 incomingTradedToken
    )
        internal
    {

        (uint256 rTraded, /*uint256 rReserved*/, /*uint256 priceTraded*/) = _uniswapReserves();

        uint256 r3 = 
            sqrt(
                (rTraded + incomingTradedToken)*(rTraded)
            ) - rTraded; //    
        require(r3 > 0 && incomingTradedToken > r3, "BAD_AMOUNT");
        // remaining (r2-r3) we will exchange at uniswap to traded token
        
         // claim to address(this)
        _mint(address(this), incomingTradedToken, "", "");
        
        uint256 amountReserveToken = doSwapOnUniswap(tradedToken, reserveToken, r3, address(internalLiquidity));
        uint256 amountTradedToken = incomingTradedToken - r3;
        
        ERC777(tradedToken).transfer(address(internalLiquidity), amountTradedToken);
        // require(
        //     ERC777(tradedToken).approve(uniswapRouter, amountTradedToken)
        //     && ERC777(reserveToken).approve(uniswapRouter, amountReserveToken),
        //     "APPROVE_FAILED"
        // );

        internalLiquidity.addLiquidity();
        

    }
    // do swap for internal liquidity contract
    function doSwapOnUniswap(
        address tokenIn, 
        address tokenOut, 
        uint256 amountIn,
        address beneficiary
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
                amountIn, 0, path, beneficiary, block.timestamp
            );

            amountOut = outputAmounts[1];
        }
    }

    
    function getTradedAveragePrice(
    ) 
        /*internal */
        public
        view
        returns(FixedPoint.uq112x112 memory)
    {

        uint64 blockTimestamp = currentBlockTimestamp();
 //console.log("1");
        uint price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
        //uint price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
//console.log("2");
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;
//console.log("3");
        uint64 windowSize = (blockTimestamp - startupTimestamp)*averagePriceWindow/FRACTION;
//console.log("4");
        if (timeElapsed > windowSize && timeElapsed>0) {
            // console.log("5");
            // console.log("price0Cumulative                       =", price0Cumulative);
            // console.log("pairObservation.price0CumulativeLast   =", pairObservation.price0CumulativeLast);
            // console.log("timeElapsed                            =", timeElapsed);
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