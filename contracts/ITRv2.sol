// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

//import "hardhat/console.sol";

//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
//import "@uniswap/v2-periphery/contracts/libraries/UniswapV2OracleLibrary.sol";

import "./libs/SwapSettingsLib.sol";
import "./libs/FixedPoint.sol";

/*

3. Yes. Very simple. Let’s just have two parameters “reserveToken” (USDC) and “priceDrop” which is a fraction between 0 and 1. Let’s say that the average price over the last 24 hours on USDC-ITR PancakeSwap pool is X. Then addLiquidity(tradedTokenAmount) can mint up to that amount of tradedTokenAmount which, if totally sold to pool, will drop the price at most by priceDrop*X.
Since PancakeSwap has contant product formula the amount is easy to calculate:

lowestPrice = averagePrice * (1 - priceDrop) / 100000

currentPrice =  currentReserveTokenBalance / currentTradedTokenBalance 

So we just solve for lowestPrice

Gregory Magarshak, [29.06.2022 18:01]
traded1 * reserve1 = traded2 * reserve2

price1 = reserve1 / traded1

price2 = reserve2 / traded2

Gregory Magarshak, [29.06.2022 18:02]
reserve2 = traded1 * reserve1 / traded2

Gregory Magarshak, [29.06.2022 18:02]
so reserve2 is a function of traded2,  and so is price2

Gregory Magarshak, [29.06.2022 18:03]
price2 = traded1 * reserve1 / traded2 / traded2

Gregory Magarshak, [29.06.2022 18:03]
so we want to solve for traded2 given price2

Gregory Magarshak, [29.06.2022 18:04]
traded2 = sqrt (price2 / trader1 / reserve1) !!

Gregory Magarshak, [29.06.2022 18:04]
That’s all

Gregory Magarshak, [29.06.2022 18:05]
traded1 - traded2 is the number Y … the max number of ITR tokens that can be minted

price1 is current price

price2 is average price from last 24 hours times (1-priceDrop) formula I wrote above



addLiquidity(tradedTokenAmount) ownerOnly … mints, sells, adds liquidity, sends LP to 0x0

claim(tradedTokenAmount) ownerOnly … mints to caller

Both of them:

* calls internal _mint (not exposed publicly) 
* respects maxAddLiquidity and maxClaim

*/

// addLiquidity() which will add more ITR to liquidity pool (can’t do it directly in Uniswap, so instead ITR contract will mint, sell to pool,  
// and add liquidity, and send to zero address, and this way people know that the only thing the USDC can go to is more liquidity.)

contract ITRv2 is Ownable, ERC777, IERC777Recipient {
    using FixedPoint for *;

    struct Observation {
        uint timestamp;
        uint price0Cumulative;
        uint price1Cumulative;
    }

    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;

	uint256 internal constant FRACTION = 100000;
    
    // address internal immutable tradedToken;
    // address internal immutable reserveToken;
    // uint256 internal immutable priceDrop;
    /**
    * @custom:shortd uniswap v2 pair
    * @notice uniswap v2 pair
    */
    address public uniswapV2Pair;
    address internal uniswapRouter;
    address internal uniswapRouterFactory;
    IUniswapV2Router02 internal UniswapV2Router02;

    Observation[] pairObservation;

    // // the desired amount of time over which the moving average should be computed, e.g. 24 hours
    // uint public immutable windowSize;
    // // the number of observations stored for pair, i.e. how many price observations are stored for the window.
    // // as granularitySize increases from 1, more frequent updates are needed, but moving averages become more precise.
    // // averages are computed over intervals with sizes in the range:
    // //   [windowSize - (windowSize / granularitySize) * 2, windowSize]
    // // e.g. if the window size is 24 hours, and the granularitySize is 24, the oracle will return the average price for
    // //   the period:
    // //   [now - [22 hours, 24 hours], now]
    // uint8 public immutable granularitySize;
    // // this is redundant with granularitySize and windowSize, but stored for gas savings & informational purposes.
    // uint public immutable periodSize;

    constructor(
        string memory name,
        string memory symbol
    ) ERC777(name, symbol, new address[](0)) {

        // require(granularitySize_ > 1, "granularitySize invalid");
        // require(
        //     (periodSize = windowSize_ / granularitySize_) * granularitySize_ == windowSize_,
        //     "window not evenly divisible"
        // );
        // require(reserveToken_ != address(0), "reserveToken invalid");
        // windowSize = windowSize_;
        // granularitySize = granularitySize_;

        // tradedToken = address(this);
        // reserveToken = reserveToken_;
        // priceDrop = priceDrop_;
        
        // // setup swap addresses
        // (uniswapRouter, uniswapRouterFactory) = SwapSettingsLib.netWorkSettings();
        // UniswapV2Router02 = IUniswapV2Router02(uniswapRouter);

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777TokensRecipient"), address(this));

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

    


    
    /**
    @dev   … mints to caller
    */
    function claim(
        
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        _mint(msg.sender, tradedTokenAmount, "", "");
    }



    // ////////////////////////////////////////////////////////////////////////
    // // internal section ////////////////////////////////////////////////////
    // ////////////////////////////////////////////////////////////////////////

    
    
    
    

   
    
    
   


}