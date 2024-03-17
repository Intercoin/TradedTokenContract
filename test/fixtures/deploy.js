const { constants } = require("@openzeppelin/test-helpers");

async function deploy() {
    const FRACTION = 10000n;
    const [
        owner, alice, bob, charlie
    ] = await ethers.getSigners();

    const lockupIntervalDay = 1n; // one day
    const lockupIntervalAmount = 365n; // year in days

    const pricePercentsDrop = 10n;// 10% = 0.1   (and multiple fraction)
    const priceDrop = FRACTION * pricePercentsDrop / 100n;// 10% = 0.1   (and multiple fraction)
    const minClaimPriceNumerator = 1n;
    const minClaimPriceDenominator = 1000n;
    const minClaimPriceGrowNumerator = 1n;
    const minClaimPriceGrowDenominator = 1000n;
    const taxesInfo = [
        0,//buytax
        0,//selltax
        0,
        0,
        false,
        false
    ];
    const RateLimitDuration = 0; // no panic
    const RateLimitValue = 0; // no panic

    const maxBuyTax = FRACTION*15n/100n; // 0.15*fraction
    const maxSellTax = FRACTION*20n/100n;// 0.20*fraction
    const holdersMax = 100n;

    const buySellToken = constants.ZERO_ADDRESS;
    const buyPrice = FRACTION*10n/100n; // 0.1 bnb for token
    const sellPrice = FRACTION*5n/100n; // 0.05 bnb for token

    const StructTaxes = [
        maxBuyTax,
        maxSellTax,
        holdersMax
    ];
    
    const StructBuySellPrice = [
        buySellToken,
        buyPrice,
        sellPrice
    ];

    const claimFrequency = 60n;  // 1 min
    const externalTokenExchangePriceNumerator = 1n;
    const externalTokenExchangePriceDenominator = 1n;

    const TaxesLib = await ethers.getContractFactory("TaxesLib");
    
    const library = await TaxesLib.deploy();
    await library.waitForDeployment();

    const TradedTokenF = await ethers.getContractFactory("TradedTokenMock",  {
        libraries: {
            TaxesLib:library.target
        }
    });

    const ERC777MintableF = await ethers.getContractFactory("ERC777Mintable");
    const ERC20MintableF = await ethers.getContractFactory("ERC20Mintable");
    const DistributionManagerF = await ethers.getContractFactory("DistributionManager");
    const ClaimManagerF = await ethers.getContractFactory("ClaimManagerMock");

    const tokenName = "Intercoin Investor Token";
    const tokenSymbol = "ITR";

    var libData = await ethers.getContractFactory("@intercoin/liquidity/contracts/LiquidityLib.sol:LiquidityLib");    
    const liquidityLib = await libData.deploy();

    return {
        owner, alice, bob, charlie,
        tokenName,
        tokenSymbol,
        lockupIntervalDay,
        lockupIntervalAmount,
        pricePercentsDrop,
        priceDrop,
        minClaimPriceNumerator,
        minClaimPriceDenominator,
        minClaimPriceGrowNumerator,
        minClaimPriceGrowDenominator,
        taxesInfo,
        RateLimitDuration,
        RateLimitValue,
        maxBuyTax,
        maxSellTax,
        holdersMax,
        buySellToken,
        buyPrice,
        sellPrice,
        StructTaxes,
        StructBuySellPrice,
        claimFrequency,
        externalTokenExchangePriceNumerator,
        externalTokenExchangePriceDenominator,
        TaxesLib,
        liquidityLib,
        TradedTokenF,
        ERC777MintableF,
        ERC20MintableF,
        DistributionManagerF,
        ClaimManagerF
    }
}

module.exports = {
  deploy
}