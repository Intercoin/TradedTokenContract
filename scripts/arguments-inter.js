const helperAddresses = require('./helpers/usdcAddress.js');
const FRACTION = 10000n;
module.exports =  [
  //CommonSettings memory commonSettings,
  [
    "Intercoin X", // string memory tokenName_,
    "INTER",// string memory tokenSymbol_,
    helperAddresses.getUSDCAddress(), // address reserveToken_, //” (USDT)
    1000, // uint256 priceDrop_, 10%
    31536000,// 1 year // uint64 durationSendBack, time in seconds when tokens can send back to exchange after claiming
  ],
  // TradedToken.ClaimSettings memory claimSettings,
  [
    [0,10], // PriceNumDen minClaimPrice;   // no claim price
    [0,10], // PriceNumDen minClaimPriceGrow; // cant change or increase minClaimPrice
  ],
  // TaxesLib.TaxesInfoInit memory taxesInfoInit,
  [
    0, // uint16 buyTax;  burnt parts of tokens when buy from uniswap //(amount * tax) / FRACTION; 
    0, // uint16 sellTax; burn when sell to uniswap
    0, //uint16 buyTaxDuration;
    0, //uint16 sellTaxDuration;
    false, //bool buyTaxGradual;
    false //bool sellTaxGradual;
  ],
  // RateLimit memory panicSellRateLimit_,
  // And panicSell globally is max 10% in a day 
  [ // means no limit
    86400, // uint32 duration;  
    1000 // uint32 fraction; 
  ],
  // TaxStruct memory taxStruct,
  [
    0n, //FRACTION*0n/100n, // uint256 buyTaxMax_,
    0n, //FRACTION*10n/100n, // uint256 sellTaxMax_
    0 //holdersMax
  ],

  // BuySellStruct memory buySellStruct,
  [ 
    helperAddresses.getUSDCAddress(), // address buySellToken;
    FRACTION*10n, // 10 USDC за 1 TRADEDTOKEN // uint256 buyPrice;   // [amount * FRACTION / buyPrice]
    0n   // 0.05 bnb for token// uint256 sellPrice;           // [amount * sellPrice / FRACTION]
  ],
  // IStructs.Emission memory emission_,
  [
    ethers.parseEther('684931'), // uint128 amount; (of tokens) //  500_000_000 first 2 years
    86400, //uint32 frequency; // in seconds                    // 1 day 
    86400n*365n*2n, // uint32 period; // in seconds                // 2 years 
    5000, // uint32 decrease; // out of FRACTION 10,000         // 50%
    0 //int32 priceGainMinimum; // out of FRACTION 10,000       // 0  block claims if price go down
  ],
  "0x1eA4C4613a4DfdAEEB95A261d11520c90D5d6252" // address liquidityLib_
];
