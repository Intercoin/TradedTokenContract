// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "../libs/FixedPoint.sol";
import "@intercoin/liquidity/contracts/interfaces/ILiquidityLib.sol";

import "../interfaces/IStructs.sol";

//import "hardhat/console.sol";

contract Liquidity is IERC777Recipient {
    address private _owner;
    address internal immutable token0;
    address internal immutable token1;
    
    address internal immutable uniswapV2Pair;
    bool internal immutable token01;
    ILiquidityLib public immutable liquidityLib;

    address internal uniswapRouter;
    address internal uniswapRouterFactory;

    uint256 internal k1;
    uint256 internal k2;
    uint256 internal k3;
    uint256 internal k4;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    // uint32 internal blockTimestampPrevPrev;
    // uint256 internal priceReservedCumulativePrevPrev;

    // values more that emission.frequency
    uint32 internal blockTimestampPrev;
    uint256 internal priceReservedCumulativePrev;
    uint256 internal twapPricePrev;

    // values before that emission.frequency
    // prev = last when blockTimestampCurrent - blockTimestampLast > emission.frequency
    uint32 internal blockTimestampLast;
    uint256 internal priceReservedCumulativeLast;
    uint256 internal twapPriceLast;

    //calcualted like this:
    // (lastPrice - prevPrice) / prevPrice
    int32 internal priceGain;

    Observation internal pairObservation;

    uint64 internal constant AVERAGE_PRICE_WINDOW = 5;
    uint64 internal constant FRACTION = 10000;
    uint64 internal constant MIN_CLAIM_PRICE_UPDATED_TIME = 1 days;

    uint64 internal startupTimestamp; // should setup after adding initial liquidity
    uint256 public totalCumulativeClaimed;
    uint256 internal amountClaimedInLastPeriod;
    uint64 internal lastClaimedTime;
    uint64 internal lastUpdatedAveragePriceTime;

    /**
     * 
     * @notice price drop (mul by fraction)
     */
    uint256 public immutable priceDrop;

    IStructs.Emission internal emission;
    IStructs.ClaimSettings internal claimSettings;
    uint64 internal lastMinClaimPriceUpdatedTime;

    struct Observation {
        uint64 timestampLast;
        uint256 price0CumulativeLast;
        FixedPoint.uq112x112 price0Average;
    }

    // struct represent the follow things
    // --- token's `amount` available to claim every `frequency` bucket
    // --- but will decrease by `decrease` fraction every `period`
    struct Emission{
        uint128 amount; // of tokens
        uint32 frequency; // in seconds
        uint32 period; // in seconds
        uint32 decrease; // out of FRACTION 10,000
        int32 priceGainMinimum; // out of FRACTION 10,000
    }

    error AccessDenied();
    error EmptyReserves();
    error PriceDropTooBig();
    error BadAmount();
    error NeedsApproval();
    error EmptyAccountAddress();
    error InputAmountCanNotBeZero();
    error PriceMayBecomeLowerThanMinClaimPrice();
    error ClaimValidationError();
    error ZeroDenominator();
    error ShouldBeMoreThanMinClaimPrice();
    error MinClaimPriceGrowTooFast();

    constructor(
        address token0_,
        address token1_,
        address uniswapPair_,
        uint256 priceDrop_,
        address liquidityLib_,
        IStructs.Emission memory emission_,
        IStructs.ClaimSettings memory claimSettings_
    ) {
        token0 = token0_;
        token1 = token1_;
        
        uniswapV2Pair = uniswapPair_;
        token01 = (IUniswapV2Pair(uniswapV2Pair).token0() == token0_);

        _owner = msg.sender;

        startupTimestamp = _currentBlockTimestamp();
        lastMinClaimPriceUpdatedTime = _currentBlockTimestamp();
        lastUpdatedAveragePriceTime = _currentBlockTimestamp();
        pairObservation.timestampLast = _currentBlockTimestamp();

        priceDrop = priceDrop_;

        emission = emission_;
        claimSettings = claimSettings_;

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        // setup swap addresses
        liquidityLib = ILiquidityLib(liquidityLib_);
        (uniswapRouter, uniswapRouterFactory) = liquidityLib.uniswapSettings();

        (k1, k2, k3, k4,/*k5*/,/*k6*/) = liquidityLib.koefficients();

    }

    function onlyCreator() internal view{
        if (msg.sender != _owner) {
            revert AccessDenied();
        }
    }

    /**
     * adding liquidity for all available balance
     */
    function addLiquidity() external {
        uint256 token0Amount = IERC20(token0).balanceOf(address(this));
        uint256 token1Amount = IERC20(token1).balanceOf(address(this));

        _addLiquidity(token0Amount, token1Amount);
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

    /**
     * approve tokens to uniswap router obtain LP tokens and move to zero address
     */
    function _addLiquidity(uint256 token0Amount, uint256 token1Amount) internal {
        
        IERC20(token0).approve(address(uniswapRouter), token0Amount);
        IERC20(token1).approve(address(uniswapRouter), token1Amount);

        //(/* uint256 A*/, /*uint256 B*/, /*uint256 lpTokens*/) =
        IUniswapV2Router02(uniswapRouter).addLiquidity(
            token0,
            token1,
            token0Amount,
            token1Amount,
            0, // there may be some slippage
            0, // there may be some slippage
            address(0),
            block.timestamp
        );
    }

    ////////////////////////////////////////////
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external {
        onlyCreator();

        startupTimestamp = _currentBlockTimestamp();

        _addLiquidity(amountTradedToken, amountReserveToken);

        // // update initial prices
        uint112 reserve0; 
        uint112 reserve1;
        uint32 blockTimestampCurrent;
        (reserve0, reserve1, blockTimestampCurrent, /*priceReservedCumulativeLast*/) = _uniswapReserves();
       
        // // update
        //priceReservedCumulativeLast = uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0));
        priceReservedCumulativeLast = (uint224(reserve1) * (2**112))/uint224(reserve0);
        twapPriceLast = priceReservedCumulativeLast;
        blockTimestampLast = blockTimestampCurrent;

        priceReservedCumulativePrev = priceReservedCumulativeLast;
        twapPricePrev = twapPriceLast;
        blockTimestampPrev = blockTimestampLast;
    }

    /**
     * @notice wrapper for getting uniswap reserves function. we use `token01` var here to be sure that reserve0 and token0 are always traded token data
     */
    function _uniswapReserves()
        internal
        view
        returns (
            // reserveTraded, reserveReserved, blockTimestampLast, priceReservedCumulativeLast
            uint112,
            uint112,
            uint32,
            uint256
        )
    {
        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast_) = IUniswapV2Pair(uniswapV2Pair).getReserves();
        if (reserve0 == 0 || reserve1 == 0) {
            revert EmptyReserves();
        }

        uint256 priceCumulativeLast;
        if (token01) {
            priceCumulativeLast = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
            return (reserve0, reserve1, blockTimestampLast_, priceCumulativeLast);
        } else {
            priceCumulativeLast = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
            return (reserve1, reserve0, blockTimestampLast_, priceCumulativeLast);
        }
    }

    function calculateSellTradedAndAddLiquidity(uint256 tradedTokenAmount) external view returns(uint256 traded2Swap, uint256 traded2Liq) {

        uint256 tradedReserve1;
        uint256 tradedReserve2;
        uint256 priceAverageData; // it's fixed point uint224

        uint256 rTraded;
        uint256 rReserved;

        uint256 reserved2Liq;

        FixedPoint.uq112x112 memory averageWithPriceDrop;

        (tradedReserve1, tradedReserve2, priceAverageData) = _maxAddLiquidity();

        bool err = (
            tradedReserve1 >= tradedReserve2 || 
            tradedTokenAmount > (tradedReserve2 - tradedReserve1)
        );

        if (!err) {
            // if tradedTokenAmount is zero, let's use the maximum amount of traded tokens allowed
            if (tradedTokenAmount == 0) {
                tradedTokenAmount = tradedReserve2 - tradedReserve1;
            }

            (rTraded, rReserved, traded2Swap, traded2Liq, reserved2Liq) = _calculateSellTradedAndLiquidity(
                tradedTokenAmount
            );

            averageWithPriceDrop = (
                FixedPoint.muluq(
                    FixedPoint.uq112x112(uint224(priceAverageData)),
                    FixedPoint.muluq(
                        FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)),
                        FixedPoint.fraction(1, FRACTION)
                    )   
                )
            );

            // "new_current_price" should be more than "average_price(1-price_drop)"
            if (
                FixedPoint.fraction(rReserved, rTraded + traded2Swap + traded2Liq)._x <=
                averageWithPriceDrop._x
            ) {
                err = true;
            }
        }

        if (err) {
            revert PriceDropTooBig();
        }
    }

    // here expecting that tradedtokens(traded2Swap+traded2Liq) is already on internalLiquidity contract
    function swapAndAddLiquidity(uint256 traded2Swap, uint256 traded2Liq) external {
        onlyCreator();
     
        // claim to address(this) necessary amount to swap from traded to reserved tokens
        uint256 reserved2Liq = _doSwapOnUniswap(traded2Swap);

        _addLiquidity(traded2Liq, reserved2Liq);

        _update();
    }

    function _doSwapOnUniswap(
        uint256 amount0ToSwap
    ) internal returns (uint256 amount0Out) {
        if (!IERC20(token0).approve(address(uniswapRouter), amount0ToSwap)) {
            revert NeedsApproval();
        }

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);
        // amountOutMin is set to 0, so only do this with pairs that have deep liquidity

        uint256[] memory outputAmounts = IUniswapV2Router02(uniswapRouter).swapExactTokensForTokens(
            amount0ToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        amount0Out = outputAmounts[1];
    }

    function _update() internal {
        uint64 blockTimestamp = _currentBlockTimestamp();
        uint64 timeElapsed = blockTimestamp - pairObservation.timestampLast;

        uint64 windowSize = ((blockTimestamp - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        if (timeElapsed > windowSize && timeElapsed > 0) {
            uint256 price0Cumulative = token01
                ? IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast()
                : IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
            pairObservation.price0Average = FixedPoint.divuq(
                FixedPoint.uq112x112(uint224(price0Cumulative - pairObservation.price0CumulativeLast)),
                FixedPoint.encode(timeElapsed)
            );
                
            pairObservation.price0CumulativeLast = price0Cumulative;

            pairObservation.timestampLast = blockTimestamp;
        }
    }

    function _calculateSellTradedAndLiquidity(uint256 incomingTradedToken)
        internal
        view
        returns (
            uint256 rTraded,
            uint256 rReserved,
            uint256 traded2Swap,
            uint256 traded2Liq,
            uint256 reserved2Liq
        )
    {
        (
            rTraded,
            rReserved, 
            /*uint32 blockTimestampLast*/,
            /*price cumulative last*/
        ) = _uniswapReserves();
        traded2Swap = (_sqrt(rTraded*(incomingTradedToken*k1 + rTraded*k2)) - rTraded*k3) / k4;

        if (traded2Swap <= 0 || incomingTradedToken <= traded2Swap) {
            revert BadAmount();
        }

        reserved2Liq = IUniswapV2Router02(uniswapRouter).getAmountOut(traded2Swap, rTraded, rReserved);
        traded2Liq = incomingTradedToken - traded2Swap;
    }

    function _maxAddLiquidity()
        internal
        view
        returns (
            //      traded1 -> traded2->priceAverageData
            uint256,
            uint256,
            uint256
        )
    {
        // tradedNew = Math.sqrt(@tokenPair.r0 * @tokenPair.r1 / (average_price*(1-@price_drop)))

        uint112 traded;
        uint112 reserved;
        uint32 blockTimestampLast_;

        (traded, reserved, blockTimestampLast_,) = _uniswapReserves();
        FixedPoint.uq112x112 memory priceAverageData = _tradedAveragePrice();

        uint256 tradedNew = FixedPoint.decode(
            FixedPoint.muluq(
                FixedPoint.muluq(
                    FixedPoint.encode(uint112(_sqrt(traded))),//q1,
                    FixedPoint.encode(uint112(_sqrt(reserved)))//q2
                ),
                FixedPoint.muluq(
                    FixedPoint.encode(uint112(_sqrt(FRACTION))),
                    FixedPoint.divuq(
                        FixedPoint.encode(uint112(1)), 
                        FixedPoint.sqrt(
                            FixedPoint.muluq(
                                priceAverageData,
                                FixedPoint.muluq(
                                    FixedPoint.encode(uint112(uint256(FRACTION) - priceDrop)),
                                    FixedPoint.fraction(1, FRACTION)
                                )
                            )
                        )
                        //q3
                    )
                )
            )
        );

        return (traded, tradedNew, priceAverageData._x);
    }

    function _tradedAveragePrice() internal view returns (FixedPoint.uq112x112 memory) {
        //uint64 blockTimestamp = _currentBlockTimestamp();
        uint256 price0Cumulative = token01 
            ? IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast() 
            : IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();
        uint64 timeElapsed = _currentBlockTimestamp() - pairObservation.timestampLast;
        uint64 windowSize = ((_currentBlockTimestamp() - startupTimestamp) * AVERAGE_PRICE_WINDOW) / FRACTION;

        if (timeElapsed > windowSize
        && timeElapsed > 0
        && price0Cumulative > pairObservation.price0CumulativeLast) {
            return FixedPoint.uq112x112(
                uint224(price0Cumulative - pairObservation.price0CumulativeLast) / uint224(timeElapsed)
            );
        }
        //use stored
        return pairObservation.price0Average;
    }

    /**
     * @notice helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**64 - 1]
     */
    function _currentBlockTimestamp() internal view returns (uint64) {
        return uint64(block.timestamp);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 result) {
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
        if (xAux >= 0x4) {
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

    function updateAveragePrice() external {
        onlyCreator();
        _updateAveragePrice();
    }

    function validateClaim(uint256 tradedTokenAmount, address account) external {
        onlyCreator();

        if (account == address(0)) {
            revert EmptyAccountAddress();
        }

        if (tradedTokenAmount == 0) {
            revert InputAmountCanNotBeZero();
        }

        (   
            uint256 availableToClaim_,
            uint256 amountOut, 
            bool priceMayBecomeLowerThanMinClaimPrice,
            /*uint112 _reserve0*/, 
            /*uint112 _reserve1*/, 
            uint32 blockTimestampCurrent, 
            uint256 priceReservedCumulativeCurrent, 
            uint256 twapPriceCurrent,
            uint256 currentAmountClaimed
        ) = __availableToClaim(tradedTokenAmount);

        // update twap price and emission things
        _updateAveragePrice();
        //----
        amountClaimedInLastPeriod = currentAmountClaimed + tradedTokenAmount;

        totalCumulativeClaimed += tradedTokenAmount;
        lastClaimedTime = uint64(block.timestamp);

        if (priceMayBecomeLowerThanMinClaimPrice) {
            revert PriceMayBecomeLowerThanMinClaimPrice();
        }

        if (
            amountOut == 0 ||
            availableToClaim_ < tradedTokenAmount
        ) {
            revert ClaimValidationError();
        }
    }

    function _availableToClaim(
        uint256 amountIn
    ) 
        external
        view 
        returns(
            uint256 availableToClaim_, 
            uint256 amountOut,
            bool priceMayBecomeLowerThanMinClaimPrice,
            uint112 reserve0_, 
            uint112 reserve1_, 
            uint32 _blockTimestampLast, 
            uint256 _priceReservedCumulativeLast, 
            uint256 twapPriceCurrent,
            uint256 currentAmountClaimed
        ) 
    {
        return __availableToClaim(amountIn);
    }

    /**
    if amountIn == 0 we will try as max as possible
    */
    function __availableToClaim(
        uint256 amountIn
    ) 
        internal 
        view 
        returns(
            uint256 availableToClaim_, 
            uint256 amountOut,
            bool priceMayBecomeLowerThanMinClaimPrice,
            uint112 reserve0_, 
            uint112 reserve1_, 
            uint32 blockTimestampCurrent, 
            uint256 priceReservedCumulativeCurrent, 
            uint256 twapPriceCurrent,
            uint256 currentAmountClaimed
        ) 
    {
        (reserve0_, reserve1_, blockTimestampCurrent, priceReservedCumulativeCurrent) = _uniswapReserves();

        // how much claimed in emission.frequency 
        // to get current bucket should use `lastClaimedTime` , not `blockTimestampCurrent`
        if (block.timestamp/emission.frequency*emission.frequency < lastClaimedTime) {
            currentAmountClaimed = amountClaimedInLastPeriod;
        } else {
            currentAmountClaimed = 0;
        }

        // how much available after calculate emission.period
        uint256 periodCount = (block.timestamp - startupTimestamp) / emission.period;
        uint256 capWithDecreasePeriod = emission.amount;

        for (uint256 i=0; i<periodCount; ++i) {
            capWithDecreasePeriod = capWithDecreasePeriod * (FRACTION-emission.decrease) / FRACTION;
        }
        // we will calculate how much available left according with Cap with decrease period
        availableToClaim_ = (currentAmountClaimed >= capWithDecreasePeriod) ? 0 : capWithDecreasePeriod - currentAmountClaimed;
        
        if (amountIn != 0) {
            //amountIn != 0
            if (amountIn > availableToClaim_) {
                availableToClaim_ = 0;
            } else {
                availableToClaim_ = amountIn;
            }
        }

        uint256 currentIterationTotalCumulativeClaimed;
        if (availableToClaim_ > 0) {
            currentIterationTotalCumulativeClaimed = totalCumulativeClaimed + availableToClaim_;
            // amountin reservein reserveout
            amountOut = IUniswapV2Router02(uniswapRouter).getAmountOut(
                currentIterationTotalCumulativeClaimed,
                reserve0_,
                reserve1_
            );

            if (amountOut == 0) {
                availableToClaim_ = 0;
            }
        }

        // priceGain updated when calling updateAveragePrice. it this method updating cumulative prices
        if (priceGain < emission.priceGainMinimum) {
            availableToClaim_ = 0;
        }
        
        if (
            //amountOut < tradedTokenAmount ||
            amountOut == 0 ||
            emission.amount < availableToClaim_ ||
            blockTimestampLast >= block.timestamp + emission.period
        ) {
            availableToClaim_ == 0;
        }

        //variables to update
        if (availableToClaim_ > 0) {
            currentAmountClaimed  += availableToClaim_;
            
        }

        if (
            claimSettings.minClaimPrice.numerator != 0 &&
            FixedPoint.fraction(reserve1_ - amountOut, reserve0_ + currentIterationTotalCumulativeClaimed)._x <=
            FixedPoint.fraction(claimSettings.minClaimPrice.numerator, claimSettings.minClaimPrice.denominator)._x
        ) {
            priceMayBecomeLowerThanMinClaimPrice = true;
        }
    }

    function restrictClaiming(IStructs.PriceNumDen memory newMinimumPrice) external {
        onlyCreator();

        if (newMinimumPrice.denominator == 0) {
            revert ZeroDenominator();
        }

        FixedPoint.uq112x112 memory newMinimumPriceFraction     = FixedPoint.fraction(newMinimumPrice.numerator, newMinimumPrice.denominator);
        FixedPoint.uq112x112 memory minClaimPriceFraction       = FixedPoint.fraction(claimSettings.minClaimPrice.numerator, claimSettings.minClaimPrice.denominator);
        FixedPoint.uq112x112 memory minClaimPriceGrowFraction   = FixedPoint.fraction(claimSettings.minClaimPriceGrow.numerator, claimSettings.minClaimPriceGrow.denominator);
        if (newMinimumPriceFraction._x <= minClaimPriceFraction._x) {
            revert ShouldBeMoreThanMinClaimPrice();
        }
        if (
            newMinimumPriceFraction._x - minClaimPriceFraction._x > minClaimPriceGrowFraction._x ||
            lastMinClaimPriceUpdatedTime <= block.timestamp + MIN_CLAIM_PRICE_UPDATED_TIME
        ) {
            revert MinClaimPriceGrowTooFast();
        }

        lastMinClaimPriceUpdatedTime = uint64(block.timestamp);
            
        claimSettings.minClaimPrice.numerator = newMinimumPrice.numerator;
        claimSettings.minClaimPrice.denominator = newMinimumPrice.denominator;
    }

    function _updateAveragePrice() internal {
        (/*reserve0_*/, /*reserve1_*/, uint32 blockTimestampCurrent, uint256 priceReservedCumulativeCurrent) = _uniswapReserves();
        // swap cumulative prices and timestamp when passed `emission.frequency` time from last swap
        // prev = last; last = current; and calcualte priceGain between prev and last
        if (_currentBlockTimestamp() - lastUpdatedAveragePriceTime > emission.frequency) {
            lastUpdatedAveragePriceTime = _currentBlockTimestamp();
            //  A - Prev
            //  B - Last     
            //  C - Current
            // twapA TwapB

            blockTimestampPrev = blockTimestampLast;
            priceReservedCumulativePrev = priceReservedCumulativeLast;

            blockTimestampLast = blockTimestampCurrent;
            priceReservedCumulativeLast = priceReservedCumulativeCurrent;

            twapPricePrev = twapPriceLast;

            if (
                blockTimestampPrev == 0 || 
                blockTimestampLast == 0 || 
                blockTimestampPrev == blockTimestampLast
            ) {
                priceGain = 0;
                //twapPriceLast =  left the same
            } else {
                twapPriceLast = (priceReservedCumulativeLast - priceReservedCumulativePrev) / (blockTimestampLast - blockTimestampPrev);

                bool sign = twapPriceLast >= twapPricePrev ? true : false;
                uint256 mod = sign ? twapPriceLast - twapPricePrev : twapPricePrev - twapPriceLast;

                priceGain = int32(int256(FRACTION * mod / twapPricePrev)) * (sign ? int32(1) : int32(-1));
            }
        }
    }

}
