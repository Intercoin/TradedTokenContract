// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../TradedToken.sol";
import "./helpers/LiquidityMock.sol";
contract TradedTokenMock is TradedToken {

    using FixedPoint for *;
 
    constructor(
        CommonSettings memory commonSettings,
        IStructs.ClaimSettings memory claimSettings_,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        TaxStruct memory taxStruct,
        BuySellStruct memory buySellStruct,
        IStructs.Emission memory emission_,
        address liquidityLib_
    ) TradedToken(commonSettings, claimSettings_, taxesInfoInit, panicSellRateLimit_, taxStruct, buySellStruct, emission_, liquidityLib_)
    {
        // override internalLiquidity
        internalLiquidity = new LiquidityMock(tradedToken, reserveToken, uniswapV2Pair, token01, commonSettings.priceDrop, liquidityLib_, emission_, claimSettings_);
        communities[address(internalLiquidity)] = true;
    }

    function mint(address account, uint256 amount) public  {
        _mint(account, amount, "", "");
    }

    function getInternalLiquidity() public view returns (address) {
        return address(internalLiquidity);
    }

    function getUniswapRouter() public view returns (address) {
        return uniswapRouter;
    }
    function getSqrt(
        uint256 x
    ) 
        public
        view 
        returns(uint256 result) 
    {
        return LiquidityMock(address(internalLiquidity)).sqrt(x);
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
        return LiquidityMock(address(internalLiquidity)).maxAddLiquidity();
    }

    // function getTradedAveragePrice(
    // ) 
    //     public
    //     view
    //     returns(FixedPoint.uq112x112 memory)
    // {
    //     return _tradedAveragePrice();
    // }

    // function totalInfo(

    // )
    //     public 
    //     view
    //     returns(
    //         uint112 r0, uint112 r1, uint32 blockTimestamp,
    //         uint price0Cumulative, uint price1Cumulative,
    //         uint64 timestampLast, uint price0CumulativeLast, uint224 price0Average
    //     )
    // {
    //     (r0, r1, blockTimestamp,) = _uniswapReserves();
    //     price0Cumulative = IUniswapV2Pair(uniswapV2Pair).price0CumulativeLast();
    //     price1Cumulative = IUniswapV2Pair(uniswapV2Pair).price1CumulativeLast();

    //     timestampLast = pairObservation.timestampLast;
    //     price0CumulativeLast = pairObservation.price0CumulativeLast;
        
    //     price0Average = pairObservation.price0Average._x;
        
    // }
    
    function setTaxesInfoInit(
        TaxesLib.TaxesInfoInit memory taxesInfoInit
    ) 
        public 
    {
        TaxesLib.setTaxes(taxesInfo, taxesInfoInit.buyTax, taxesInfoInit.sellTax);

        taxesInfo.buyTaxDuration = taxesInfoInit.buyTaxDuration;
        taxesInfo.sellTaxDuration = taxesInfoInit.sellTaxDuration;
        taxesInfo.buyTaxGradual = taxesInfoInit.buyTaxGradual;
        taxesInfo.sellTaxGradual = taxesInfoInit.sellTaxGradual;
 
    }
    function setTaxesInfoInitWithoutTaxes(
        TaxesLib.TaxesInfoInit memory taxesInfoInit
    ) 
        public 
    {

        taxesInfo.buyTaxDuration = taxesInfoInit.buyTaxDuration;
        taxesInfo.sellTaxDuration = taxesInfoInit.sellTaxDuration;
        taxesInfo.buyTaxGradual = taxesInfoInit.buyTaxGradual;
        taxesInfo.sellTaxGradual = taxesInfoInit.sellTaxGradual;
 
    }
    
    function holdersAmount() public view returns(uint256) {
        return holdersCount;
    }

    function setRestrictClaiming(IStructs.PriceNumDen memory newMinimumPrice) external {
        LiquidityMock(address(internalLiquidity)).setRestrictClaiming(newMinimumPrice);
    }

    function setTotalCumulativeClaimed(uint256 total) public {
        totalCumulativeClaimed = total;
    }

    function getMinClaimPriceUpdatedTime() public view returns(uint64) {
        return LiquidityMock(address(internalLiquidity)).getMinClaimPriceUpdatedTime();
    }

    function setHoldersMax(uint16 i) public  {
        holdersMax = i;
    }
    
    
    function setRateLimit(
        RateLimit memory _panicSellRateLimit
    )
        external
    {
        panicSellRateLimit.duration = _panicSellRateLimit.duration;
        panicSellRateLimit.fraction = _panicSellRateLimit.fraction;
    }

    function setEmissionAmount(uint128 amount) public {
        LiquidityMock(address(internalLiquidity)).setEmissionAmount(amount);
    }

    function setEmissionFrequency(uint32 frequency) public {
        LiquidityMock(address(internalLiquidity)).setEmissionFrequency(frequency);
    }

    function setEmissionPeriod(uint32 period) public {
        LiquidityMock(address(internalLiquidity)).setEmissionPeriod(period);
    }

    function setEmissionDecrease(uint32 decrease) public {
        LiquidityMock(address(internalLiquidity)).setEmissionDecrease(decrease);
    }

    function setEmissionPriceGainMinimum(int32 priceGainMinimum) public {
        LiquidityMock(address(internalLiquidity)).setEmissionPriceGainMinimum(priceGainMinimum);
    }
    // function getBlockTimestampLast() public view returns(uint32) {
    //     return blockTimestampLast;
    // }
    
    function setReceivedTransfersCount(address addr, uint64 amount) public {
        receivedTransfersCount[addr] = amount;
    }

    
}