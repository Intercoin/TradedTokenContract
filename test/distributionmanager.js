const { ethers, waffle } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('chai');
const chai = require('chai');
const { time } = require('@openzeppelin/test-helpers');

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const DEAD_ADDRESS = '0x000000000000000000000000000000000000dEaD';
const UNISWAP_ROUTER_FACTORY_ADDRESS = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
const UNISWAP_ROUTER = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

const ZERO = BigNumber.from('0');
const ONE = BigNumber.from('1');
const TWO = BigNumber.from('2');
const THREE = BigNumber.from('3');
const FOURTH = BigNumber.from('4');
const FIVE = BigNumber.from('5');
const SIX = BigNumber.from('6');
const SEVEN = BigNumber.from('7');
const EIGHT = BigNumber.from('8');
const NINE = BigNumber.from('9');
const TEN = BigNumber.from('10');
const HUN = BigNumber.from('100');
const THOUSAND = BigNumber.from('1000');

const ONE_ETH = TEN.pow(BigNumber.from('18'));

const FRACTION = BigNumber.from('10000');

chai.use(require('chai-bignumber')());

describe("DistributionManager", function () {
    const accounts = waffle.provider.getWallets();

    const owner = accounts[0];                     
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];

    const lockupIntervalDay = 1; // one day
    const lockupIntervalAmount = 365; // year in days

    const pricePercentsDrop = 10;// 10% = 0.1   (and multiple fraction)
    const priceDrop = FRACTION.mul(pricePercentsDrop).div(HUN);// 10% = 0.1   (and multiple fraction)
    const minClaimPriceNumerator = 1;
    const minClaimPriceDenominator = 1000;
    const minClaimPriceGrowNumerator = 1;
    const minClaimPriceGrowDenominator = 1000;
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

    const maxBuyTax = FRACTION.mul(15).div(100); // 0.15*fraction
    const maxSellTax = FRACTION.mul(20).div(100);// 0.20*fraction
    const holdersMax = HUN;

    const buySellToken = ZERO_ADDRESS;
    const buyPrice = FRACTION.mul(TEN).div(HUN); // 0.1 bnb for token
    const sellPrice = FRACTION.mul(FIVE).div(HUN); // 0.05 bnb for token

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

    const claimFrequency = 60;  // 1 min
    const externalTokenExchangePriceNumerator = 1;
    const externalTokenExchangePriceDenominator = 1;

    
    var TaxesLib, SwapSettingsLib, TradedTokenF, ERC777MintableF, ERC20MintableF, DistributionManagerF, ClaimManagerF;


    beforeEach("deploying", async() => {
        TaxesLib = await ethers.getContractFactory("TaxesLib");
        const library = await TaxesLib.deploy();
        await library.deployed();

        TradedTokenF = await ethers.getContractFactory("TradedTokenMock",  {
            libraries: {
                TaxesLib:library.address
            }
        });

        ERC777MintableF = await ethers.getContractFactory("ERC777Mintable");
        ERC20MintableF = await ethers.getContractFactory("ERC20Mintable");
        DistributionManagerF = await ethers.getContractFactory("DistributionManager");
        ClaimManagerF = await ethers.getContractFactory("ClaimManagerMock");

        
    });

    describe("simple ERC20/ERC777 operations", function () {
        var nevermindToken;
        beforeEach("deploying", async() => {
            nevermindToken = await ERC20MintableF.deploy("somename","somesymbol");
        });

        it("distributionManager should receive and transfer any erc20 tokens", async() => {
            var simpleerc20 = await ERC20MintableF.deploy("someERC20name","someERC20symbol");

            claimManager = await ClaimManagerF.deploy(
                simpleerc20.address,
                [
                    nevermindToken.address,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );
            
            distributionManager = await DistributionManagerF.connect(owner).deploy(
                simpleerc20.address, 
                nevermindToken.address, 
                claimManager.address
            );

            const amountToMint = ONE_ETH;
            const balanceBefore = await simpleerc20.balanceOf(distributionManager.address);
            const balanceAliceBefore = await simpleerc20.balanceOf(alice.address);

            await simpleerc20.mint(distributionManager.address, amountToMint);

            const balanceAfter = await simpleerc20.balanceOf(distributionManager.address);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter.sub(balanceBefore)
            );

            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await simpleerc20.balanceOf(alice.address);
            const balanceAfterSendOut = await simpleerc20.balanceOf(distributionManager.address);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter.sub(balanceAliceBefore)
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });

        it("distributionManager should receive and send any erc777 tokens", async() => {
            var simpleerc777 = await ERC777MintableF.deploy();

            claimManager = await ClaimManagerF.deploy(
                simpleerc777.address,
                [
                    nevermindToken.address,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );
            
            distributionManager = await DistributionManagerF.connect(owner).deploy(
                simpleerc777.address, 
                nevermindToken.address, 
                claimManager.address
            );

            const amountToMint = ONE_ETH;
            const balanceBefore = await simpleerc777.balanceOf(distributionManager.address);
            const balanceAliceBefore = await simpleerc777.balanceOf(alice.address);

            await simpleerc777.mint(distributionManager.address, amountToMint);

            const balanceAfter = await simpleerc777.balanceOf(distributionManager.address);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter.sub(balanceBefore)
            );

            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await simpleerc777.balanceOf(alice.address);
            const balanceAfterSendOut = await simpleerc777.balanceOf(distributionManager.address);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter.sub(balanceAliceBefore)
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });
    });

    describe("tests with TradedToken", function () {
        var distributionManager, claimManager;
        var erc20token, erc777token, externalToken,tradedTokenInstance;
        var liquidityLib;

        beforeEach("deploying", async() => {
            erc20ReservedToken  = await ERC20MintableF.deploy("ERC20 Reserved Token", "ERC20-RSRV");
            externalToken       = await ERC20MintableF.deploy("ERC20 External Token", "ERC20-EXT");
            erc20token          = await ERC20MintableF.deploy("ERC20Token", "ERC20T");
            erc777token         = await ERC777MintableF.deploy();
        
            var libData = await ethers.getContractFactory("@intercoin/liquidity/contracts/LiquidityLib.sol:LiquidityLib");    
            liquidityLib = await libData.deploy();

            tradedTokenInstance = await TradedTokenF.connect(owner).deploy(
                "Intercoin Investor Token",
                "ITR",
                erc20ReservedToken.address, //” (USDC)
                priceDrop,
                lockupIntervalAmount,
                [
                    [minClaimPriceNumerator, minClaimPriceDenominator],
                    [minClaimPriceGrowNumerator, minClaimPriceGrowDenominator]
                ],
                taxesInfo,
                [RateLimitDuration, RateLimitValue],
                StructTaxes,
                StructBuySellPrice,
                liquidityLib.address
            );

            claimManager = await ClaimManagerF.deploy(
                tradedTokenInstance.address,
                [
                    externalToken.address,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );

            distributionManager = await DistributionManagerF.connect(owner).deploy(
                tradedTokenInstance.address, 
                externalToken.address, 
                claimManager.address
            );

            

        });

        it("distributionManager should receive and send TradedToken", async() => {
           
            const amountToMint = ONE_ETH;
            const balanceBefore = await tradedTokenInstance.balanceOf(distributionManager.address);
            const balanceAliceBefore = await tradedTokenInstance.balanceOf(alice.address);

            await tradedTokenInstance.mint(distributionManager.address, amountToMint);

            const balanceAfter = await tradedTokenInstance.balanceOf(distributionManager.address);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter.sub(balanceBefore)
            );
            //--
            await tradedTokenInstance.connect(owner).addManager(distributionManager.address);
            //--
            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await tradedTokenInstance.balanceOf(alice.address);
            const balanceAfterSendOut = await tradedTokenInstance.balanceOf(distributionManager.address);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter.sub(balanceAliceBefore)
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });

        it.only("distributionManager should call wantToClaim", async() => {
            const claimAmount = ONE_ETH;
            var mapBefore = await claimManager.wantToClaimMap(distributionManager.address);
await distributionManager.connect(owner).wantToClaim(claimAmount);            
            await expect(distributionManager.connect(owner).wantToClaim(claimAmount)).to.be.revertedWith("InsufficientAmount");
            await externalToken.mint(distributionManager.address, claimAmount);
            await distributionManager.connect(owner).wantToClaim(claimAmount);

            var mapAfter = await claimManager.wantToClaimMap(distributionManager.address);

            expect(mapBefore.amount).to.be.eq(ZERO);
            expect(mapAfter.amount).to.be.eq(claimAmount);
            
        });

        it("distributionManager should call claim", async() => {
            const claimAmount = ONE_ETH;
            var bobBalanceBefore = await tradedTokenInstance.balanceOf(bob.address);
            
            await expect(distributionManager.connect(owner).wantToClaim(claimAmount)).to.be.revertedWith("InsufficientAmount");
            await externalToken.mint(distributionManager.address, claimAmount);
            await distributionManager.connect(owner).wantToClaim(claimAmount);

            // try#1
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWith('ClaimTooFast');
            //pass time
            await time.increase(claimFrequency);

            // try#2
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWith('EmptyReserves');
            //add reserves and initial liquidity
            await erc20ReservedToken.connect(owner).mint(tradedTokenInstance.address, ONE_ETH.mul(THOUSAND));
            await tradedTokenInstance.connect(owner).addInitialLiquidity(ONE_ETH.mul(THOUSAND), ONE_ETH.mul(TEN));

            // try#3
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWith('OwnerAndManagersOnly');
            // claimManager contract should be a manager on tradedToken
            await tradedTokenInstance.connect(owner).addManager(claimManager.address);

            // try#4
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWith('ClaimsDisabled');
            //-- need to enable claim mode 
            await tradedTokenInstance.connect(owner).enableClaims();
            
            // finally claim completely
            await distributionManager.connect(owner).claim(claimAmount,bob.address);
            var bobBalanceAfter = await tradedTokenInstance.balanceOf(bob.address);

            expect(ZERO).to.be.eq(bobBalanceBefore);
            expect(claimAmount).to.be.eq(bobBalanceAfter.sub(bobBalanceBefore));

        });

    });


    
    
})