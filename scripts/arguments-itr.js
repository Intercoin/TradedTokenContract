const helperAddresses = require('./helpers/busdAddress.js');

module.exports =  [
  "Intercoin", // string memory tokenName_,
  "ITR",// string memory tokenSymbol_,
  helperAddresses.getBUSDAddress(), // address reserveToken_, //” (USDC)
  1000, // uint256 priceDrop_,
  365,// uint64 lockupIntervalAmount_,
  // TradedToken.ClaimSettings memory claimSettings,
  [
    [1,10], // PriceNumDen minClaimPrice;
    [1,10], // PriceNumDen minClaimPriceGrow;
  ],
  // TaxesLib.TaxesInfoInit memory taxesInfoInit,
  [
    0, //uint16 buyTaxDuration;
    0, //uint16 sellTaxDuration;
    false, //bool buyTaxGradual;
    false //bool sellTaxGradual;
  ],
  //RateLimit memory panicSellRateLimit_,
  //And panicSell globally is max 10% in a day 
  [ // means no limit
    86400, // uint32 duration;  
    0 // uint32 fraction; 
  ],
  1000, // uint256 buyTaxMax_,
  1000, // uint256 sellTaxMax_
  0 //holdersMax
];