const { constants } = require("@openzeppelin/test-helpers");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

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

    const StakeManagerF = await ethers.getContractFactory("StakeManager",  {});
    const TradedTokenImitationF = await ethers.getContractFactory("TradedTokenImitation",  {});
    
    // emission. we will setup fake values. old tests must be passed
    const emissionAmount = ethers.parseEther('100000'); // uint128 amount; // of tokens
    const emissionFrequency = 1; // uint32 frequency; // in seconds
    const emissionPeriod = 1; // uint32 period; // in seconds
    const emissionDecrease = 1000; // uint32 decrease; // out of FRACTION 10,000
    const emissionPriceGainMinimum = 5000; // int32 priceGainMinimum; // out of FRACTION 10,000

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
        emissionAmount,
        emissionFrequency,
        emissionPeriod,
        emissionDecrease,
        emissionPriceGainMinimum,
        TaxesLib,
        liquidityLib,
        TradedTokenF,
        ERC777MintableF,
        ERC20MintableF,
        DistributionManagerF,
        ClaimManagerF,
        StakeManagerF,
        TradedTokenImitationF
    }
}

async function deploy2() {
    const res = await loadFixture(deploy);
    const {
        owner,
        tokenName,
        tokenSymbol,
        priceDrop,
        lockupIntervalAmount,
        minClaimPriceNumerator, minClaimPriceDenominator,
        minClaimPriceGrowNumerator, minClaimPriceGrowDenominator,
        taxesInfo,
        externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator,
        claimFrequency,
        StructTaxes,
        StructBuySellPrice,
        emissionAmount,
        emissionFrequency,
        emissionPeriod,
        emissionDecrease,
        emissionPriceGainMinimum,

        RateLimitDuration, RateLimitValue,
        ERC20MintableF,
        ERC777MintableF,
        ClaimManagerF,
        DistributionManagerF,
        TradedTokenF,
        liquidityLib
    } = res;

    const erc20ReservedToken  = await ERC20MintableF.deploy("ERC20 Reserved Token", "ERC20-RSRV");
    const externalToken       = await ERC20MintableF.deploy("ERC20 External Token", "ERC20-EXT");

    const mainInstance = await TradedTokenF.connect(owner).deploy(
        [
            tokenName,
            tokenSymbol,
            erc20ReservedToken.target,
            priceDrop,
            lockupIntervalAmount
        ],
        [
            [minClaimPriceNumerator, minClaimPriceDenominator],
            [minClaimPriceGrowNumerator, minClaimPriceGrowDenominator]
        ],
        taxesInfo,
        [RateLimitDuration, RateLimitValue],
        StructTaxes,
        StructBuySellPrice,
        [
            emissionAmount,
            emissionFrequency,
            emissionPeriod,
            emissionDecrease,
            emissionPriceGainMinimum
        ],
        liquidityLib.target
    );

    const claimManager = await ClaimManagerF.deploy(
        mainInstance.target,
        [
            externalToken.target,
            [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
            claimFrequency
        ]
    );

    return {...res, ...{
        mainInstance,
        claimManager,
        erc20ReservedToken,
        externalToken
    }};
}


async function deploy3() {
    const res = await loadFixture(deploy2);
    const {
        owner,
        erc20ReservedToken,
        mainInstance
    } = res;

    await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));
    await mainInstance.connect(owner).addInitialLiquidity(ethers.parseEther('10'), ethers.parseEther('10'));
    return res;
}

async function deploy4() {
    const res = await loadFixture(deploy3);
    const {
        owner,
        bob,
        claimManager,
        externalToken,
        mainInstance
    } = res;
    
    await mainInstance.connect(owner).enableClaims();
    //minting to bob and approve
    await externalToken.connect(owner).mint(bob.address, ethers.parseEther('1'));
    await externalToken.connect(bob).approve(claimManager.target, ethers.parseEther('1'));

    return res;
}

async function deploy5() {
    const res = await loadFixture(deploy4);
    const {
        bob,
        claimFrequency,
        claimManager
    } = res;
    
    //await claimManager.connect(bob).wantToClaim(ONE_ETH);
    await claimManager.connect(bob).wantToClaim(0); // all awailable
    // pass time 
    await time.increase(claimFrequency);

    return res;
}

async function deployInPresale() {
    const res = await loadFixture(deploy2);
    const {
        lockupIntervalAmount
    } = res;

    const ts = await time.latest();
    const timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

    const PresaleF = await ethers.getContractFactory("PresaleMock");
    const Presale = await PresaleF.deploy();

    return {...res, ...{
        ts,
        timeUntil,
        Presale
    }};
}

async function deployAndTestUniswapSettings() {
    const res = await loadFixture(deploy3);
    const {
        mainInstance
    } = res;

    const UNISWAP_ROUTER = await mainInstance.getUniswapRouter();
    uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

    const storedBuyTax = await mainInstance.buyTax();
    const storedSellTax = await mainInstance.sellTax();

    return {...res, ...{
        storedBuyTax,
        storedSellTax,
        uniswapRouterInstance
    }};
}         

 async function deployAndTestUniswapSettingsWithFirstSwap() {
    const res = await loadFixture(deployAndTestUniswapSettings);
    const {
        owner,
        bob,
        lockupIntervalAmount,
        erc20ReservedToken,
        uniswapRouterInstance,
        mainInstance
    } =  res;

    await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));

    ts = await time.latest();
    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

    const smthFromOwner = 1;
    await mainInstance.connect(owner).enableClaims();
    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
        ethers.parseEther('0.5'), //uint amountIn,
        0, //uint amountOutMin,
        [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
        bob.address, //address to,
        timeUntil //uint deadline   

    );

    const internalLiquidityAddress = await mainInstance.getInternalLiquidity();

    return {...res, ...{
        internalLiquidityAddress
    }};
}

module.exports = {
  deploy,
  deploy2,
  deploy3,
  deploy4,
  deploy5,
  deployInPresale,
  deployAndTestUniswapSettings,
  deployAndTestUniswapSettingsWithFirstSwap
}