// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "../TradedToken.sol";

contract TradedTokenMock is TradedToken {

    using FixedPoint for *;
 
    constructor(
        string memory tokenName_,
        string memory tokenSymbol_,
        address reserveToken_, //” (USDC)
        uint256 priceDrop_,
        uint64 lockupIntervalAmount,
        ClaimSettings memory claimSettings,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        RateLimit memory panicSellRateLimit_,
        MaxVars memory maxVars,
        BuyInfo memory buyInfo
    ) TradedToken(tokenName_, tokenSymbol_, reserveToken_, priceDrop_, lockupIntervalAmount,  claimSettings, taxesInfoInit, panicSellRateLimit_, maxVars, buyInfo)
    {
    }

    function mint(address account, uint256 amount) public  {
        _mint(account, amount, "", "");
    }

    function getInternalLiquidity() public view returns (address) {
        return address(internalLiquidity);
    }

    function getSqrt(
        uint256 x
    ) 
        public
        pure 
        returns(uint256 result) 
    {
        return _sqrt(x);
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
        uint112 traded;
        uint112 reserved;
        //uint32 blockTimestampLast;

        (traded, reserved, /*blockTimestampLast*/) = _uniswapReserves();
        //_hitAllTimeHigh(traded, reserved);
        return _maxAddLiquidity(traded, reserved);
    }

    // function getTradedAveragePrice(
    // ) 
    //     public
    //     view
    //     returns(FixedPoint.uq112x112 memory)
    // {
    //     return _tradedAveragePrice();
    // }

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

    function setRestrictClaiming(PriceNumDen memory newMinimumPrice) external {
        
        lastMinClaimPriceUpdatedTime = uint64(block.timestamp);
            
        minClaimPrice.numerator = newMinimumPrice.numerator;
        minClaimPrice.denominator = newMinimumPrice.denominator;
    }

    function setTotalCumulativeClaimed(uint256 total) public {
        cumulativeClaimed = total;
    }

    function getMinClaimPriceUpdatedTime() public pure returns(uint64) {
        return MIN_CLAIM_PRICE_UPDATED_TIME;
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

    
}