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

describe("TradedTokenInstance", function () {
    const accounts = waffle.provider.getWallets();

    const owner = accounts[0];                     
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];
    
    const HOUR = 60*60; // * interval: HOUR in seconds
    const DAY = 24*HOUR; // * interval: DAY in seconds

    const lockupIntervalDay = 1; // one day
    const lockupIntervalAmount = 365; // year in days

    const tokenName = "Intercoin Investor Token";
    const tokenSymbol = "ITR";
    // const defaultOperators = [];
    // const initialSupply = TEN.mul(TEN.pow(SIX)).mul(TENIN18); // 10kk * 10^18
    // const maxTotalSupply = TEN.mul(TEN.pow(NINE)).mul(TENIN18); // 10kkk * 10^18
    const reserveToken = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; //” (USDC)
    const pricePercentsDrop = 10;// 10% = 0.1   (and multiple fraction)
    const priceDrop = FRACTION.mul(pricePercentsDrop).div(HUN);// 10% = 0.1   (and multiple fraction)
    
    const minClaimPriceNumerator = 1;
    const minClaimPriceDenominator = 1000;

    const minClaimPriceGrowNumerator = 1;
    const minClaimPriceGrowDenominator = 1000;

    const externalTokenExchangePriceNumerator = 1;
    const externalTokenExchangePriceDenominator = 1;

    const RateLimitDuration = 0; // no panic
    const RateLimitValue = 0; // no panic

    const maxBuyTax = FRACTION.mul(15).div(100); // 0.15*fraction
    const maxSellTax = FRACTION.mul(20).div(100);// 0.20*fraction
    const holdersMax = HUN;

    const claimFrequency = 60;  // 1 min

    const taxesInfo = [
        0,
        0,
        false,
        false
    ];

    // vars
    var mainInstance, erc20ReservedToken;
    var MainFactory, ERC20Factory;
    
    
    var printPrices = async function(str) {
        return;
        console.log(mainInstance.address);
        let x1,x2,x3,x4,x5;
        [x1,x2,x3,x4,x5] = await mainInstance.uniswapPrices();
        console.log("======"+str+"============================");
        console.log("reserveTraded  = ",x1.toString());
        console.log("reserveReserved= ",x2.toString());
        console.log("priceTraded    = ",x3.toString());
        console.log("priceReserved  = ",x4.toString());
        console.log("blockTimestamp = ",x5.toString());

    }                

    beforeEach("deploying", async() => {
        const TaxesLib = await ethers.getContractFactory("TaxesLib");
        const library = await TaxesLib.deploy();
        await library.deployed();

        const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
        const library2 = await SwapSettingsLib.deploy();
        await library2.deployed();

        MainFactory = await ethers.getContractFactory("TradedTokenMock",  {
            libraries: {
                TaxesLib:library.address,
                SwapSettingsLib:library2.address
            }
        });
        
        ERC20Factory = await ethers.getContractFactory("ERC20Mintable");
    });
/*
    

    it("should external claim if exchange price 1:2", async() => {

        // make snapshot before time manipulations
        let snapId = await ethers.provider.send('evm_snapshot', []);
                    
        var erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
        var externalToken       = await ERC20Factory.deploy("ERC20 External Token", "ERC20-EXT");
        const customExternalTokenExchangePriceNumerator = 1;
        const customExternalTokenExchangePriceDenominator = 2;

        mainInstance = await MainFactory.connect(owner).deploy(
            "Intercoin Investor Token",
            "ITR",
            erc20ReservedToken.address, //” (USDC)
            priceDrop,
            lockupIntervalAmount,
            [
                externalToken.address,
                [minClaimPriceNumerator, minClaimPriceDenominator],
                [minClaimPriceGrowNumerator, minClaimPriceGrowDenominator],
                [customExternalTokenExchangePriceNumerator, customExternalTokenExchangePriceDenominator],
                claimFrequency
            ],
            taxesInfo,
            0,
            0,
            holdersMax
        );
        await expect(
            mainInstance.availableToClaimByAddress(bob.address)
        ).to.be.revertedWith(`EmptyReserves()`);

        await erc20ReservedToken.connect(owner).mint(owner.address, ONE_ETH.mul(TEN));
        await erc20ReservedToken.connect(owner).transfer(mainInstance.address, ONE_ETH.mul(TEN));

        await mainInstance.connect(owner).addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));

        await externalToken.connect(owner).mint(bob.address, ONE_ETH);
        let bobExternalTokenBalanceBefore = await externalToken.balanceOf(bob.address);
        let mainInstanceExternalTokenBalanceBefore = await externalToken.balanceOf(mainInstance.address);

        await externalToken.connect(bob).approve(mainInstance.address, ONE_ETH);

        await expect(
            mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address)
        ).to.be.revertedWith(`InsufficientAmountToClaim(${ONE_ETH.mul(customExternalTokenExchangePriceNumerator).div(customExternalTokenExchangePriceDenominator)}, ${ZERO})`);


        await mainInstance.connect(bob).wantToClaim(ONE_ETH);
        
        await mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address);

        let bobExternalTokenBalanceAfter = await externalToken.balanceOf(bob.address);
        let mainInstanceExternalTokenBalanceAfter = await externalToken.balanceOf(mainInstance.address);

        expect(await mainInstance.balanceOf(bob.address)).to.be.eq(ONE_ETH.mul(customExternalTokenExchangePriceNumerator).div(customExternalTokenExchangePriceDenominator));
        expect(bobExternalTokenBalanceBefore.sub(bobExternalTokenBalanceAfter)).to.be.eq(ONE_ETH);
        expect(mainInstanceExternalTokenBalanceAfter.sub(mainInstanceExternalTokenBalanceBefore)).to.be.eq(ZERO);

        // restore snapshot
        await ethers.provider.send('evm_revert', [snapId]);
    });

   
*/
  
    describe("validate params", function () {
       
        it("should correct reserveToken", async() => {
            await expect(
                MainFactory.connect(owner).deploy(
                    "Intercoin Investor Token",
                    "ITR",
                    ZERO_ADDRESS, //” (USDC)
                    priceDrop,
                    lockupIntervalAmount,
                    [
                        [minClaimPriceNumerator, minClaimPriceDenominator],
                        [minClaimPriceGrowNumerator, minClaimPriceGrowDenominator]
                    ],
                    taxesInfo,
                    [RateLimitDuration, RateLimitValue],
                    maxBuyTax,
                    maxSellTax,
                    holdersMax
                )
            ).to.be.revertedWith("reserveTokenInvalid()");
        });
    });


    describe("instance check", function () {
        var externalToken, claimManager, claimManagerFactory;
        beforeEach("deploying", async() => {

            

            erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
            externalToken       = await ERC20Factory.deploy("ERC20 External Token", "ERC20-EXT");

            mainInstance = await MainFactory.connect(owner).deploy(
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
                maxBuyTax,
                maxSellTax,
                holdersMax
            );

            const ReleaseManagerFactoryF = await ethers.getContractFactory("MockReleaseManagerFactory");
            const ReleaseManagerF = await ethers.getContractFactory("MockReleaseManager");
            let implementationReleaseManager    = await ReleaseManagerF.deploy();
            let releaseManagerFactory   = await ReleaseManagerFactoryF.connect(owner).deploy(implementationReleaseManager.address);
            let tx = await releaseManagerFactory.connect(owner).produce();
            let rc = await tx.wait(); // 0ms, as tx is already confirmed
            let event = rc.events.find(event => event.event === 'InstanceProduced');
            let instance;
            [instance, /*instancesCount*/] = event.args;

            let releaseManager = await ethers.getContractAt("MockReleaseManager",instance);

            const ClaimManagerF = await ethers.getContractFactory("ClaimManagerMock");
            const ClaimManagerFactoryF = await ethers.getContractFactory("ClaimManagerFactory");
            const implementationClaimManager = await ClaimManagerF.deploy();

            claimManagerFactory   = await ClaimManagerFactoryF.connect(owner).deploy(
                implementationClaimManager.address,
                ZERO_ADDRESS,
                releaseManager.address
            );

            const factoriesList = [claimManagerFactory.address];
            const factoryInfo = [
                [
                    1,//uint8 factoryIndex; 
                    1,//uint16 releaseTag; 
                    "0x53696c766572000000000000000000000000000000000000"//bytes24 factoryChangeNotes;
                ]
            ];

            await releaseManager.connect(owner).newRelease(factoriesList, factoryInfo);

            await expect(
                claimManagerFactory.produce(
                    ZERO_ADDRESS,
                    [
                        externalToken.address,
                        [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                        claimFrequency
                    ]
                )
            ).to.be.revertedWith("EmptyTokenAddress()");

            await expect(
                claimManagerFactory.produce(
                    mainInstance.address,
                    [
                        ZERO_ADDRESS,
                        [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                        claimFrequency
                    ]
                )
            ).to.be.revertedWith("EmptyTokenAddress()");

            tx = await claimManagerFactory.produce(
                mainInstance.address,
                [
                    externalToken.address,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );
            rc = await tx.wait(); // 0ms, as tx is already confirmed
            event = rc.events.find(event => event.event === 'InstanceCreated');
            
            [instance, /*instancesCount*/] = event.args;
            
            claimManager = await ethers.getContractAt("ClaimManagerMock",instance);

            // let erc777 = await mainInstance.tradedToken();
            // itrv2 = await ethers.getContractAt("ITRv2",erc777);

            
        });

        it("reverted if didn't add liquidity before", async() => {
            await expect(
                mainInstance.availableToClaim()
            ).to.be.revertedWith(`EmptyReserves()`);
        });
        
        it("should valid ClamedEnabledTime", async() => {
            expect(await mainInstance.claimsEnabledTime()).to.be.eq(ZERO);
            await expect(mainInstance.connect(bob).enableClaims()).revertedWith("Ownable: caller is not the owner");
            await mainInstance.connect(owner).enableClaims();
            expect(await mainInstance.claimsEnabledTime()).not.to.be.eq(ZERO);
            await expect(mainInstance.connect(owner).enableClaims()).revertedWith("ClaimsEnabledTimeAlreadySetup()");
        });

        it("cover sqrt func", async() => {
            expect(await mainInstance.getSqrt(0)).to.be.equal(0);
            expect(await mainInstance.getSqrt("0x100000000000000000000000000000000")).to.be.equal("0x10000000000000000");
            expect(await mainInstance.getSqrt("0x10000000000000000")).to.be.equal("0x100000000");
            expect(await mainInstance.getSqrt("0x100000000")).to.be.equal("0x10000");
            expect(await mainInstance.getSqrt("0x10000")).to.be.equal("0x100");
            expect(await mainInstance.getSqrt("0x100")).to.be.equal("0x10");
        });

        it("should correct Intercoin Investor Token", async() => {
            expect(await mainInstance.name()).to.be.equal(tokenName);
        });

        it("should correct ITR", async() => {
            expect(await mainInstance.symbol()).to.be.equal(tokenSymbol);
        });

        it("shouldnt `addLiquidity` without liquidity", async() => {
            await expect(
                mainInstance.connect(owner).addLiquidity(ONE_ETH)
            ).to.be.revertedWith("InitialLiquidityRequired()");
        }); 

        it("shouldnt addLiquidity manually without method `addInitialLiquidity`", async() => {
            let uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

            await erc20ReservedToken.mint(bob.address, ONE_ETH);
            await mainInstance.mint(bob.address, ONE_ETH);

            await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH);
            await mainInstance.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH);

            let ts = await time.latest();
            let timeUntil = parseInt(ts)+parseInt(8*DAY);

            // handle TransferHelper error although it's happens in our contract
            await expect(
                uniswapRouterInstance.connect(bob).addLiquidity(
                    mainInstance.address, //address tokenA,
                    erc20ReservedToken.address, //address tokenB,
                    ONE_ETH, //uint amountADesired,
                    ONE_ETH, //uint amountBDesired,
                    ONE_ETH, //uint amountAMin,
                    ONE_ETH, //uint amountBMin,
                    bob.address, //address to,
                    timeUntil //uint deadline
                )
            ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");

        }); 

        it("should add managers", async() => {

            await expect(
                mainInstance.connect(bob).addManager(charlie.address)
            ).to.be.revertedWith("Ownable: caller is not the owner");

            expect(await mainInstance.connect(owner).managers(bob.address)).to.be.eq(ZERO);
            await mainInstance.connect(owner).addManager(bob.address);
            expect(await mainInstance.connect(owner).managers(bob.address)).not.to.be.eq(ZERO);

            await expect(
                mainInstance.connect(bob).addManager(charlie.address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should remove managers", async() => {
            await mainInstance.connect(owner).addManager(alice.address);

            await expect(
                mainInstance.connect(bob).removeManagers([alice.address])
            ).to.be.revertedWith("Ownable: caller is not the owner");

            await mainInstance.connect(owner).addManager(bob.address);
            await expect(
                mainInstance.connect(bob).removeManagers([alice.address])
            ).to.be.revertedWith("Ownable: caller is not the owner");

            expect(await mainInstance.connect(owner).managers(alice.address)).not.to.be.eq(ZERO);
            await mainInstance.connect(owner).removeManagers([alice.address])
            expect(await mainInstance.connect(owner).managers(alice.address)).to.be.eq(ZERO);            
            
        });

        it("[cover] shouldnt claim (ClaimValidationError)", async() => {
          
            await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(THOUSAND));
            await mainInstance.addInitialLiquidity(ONE_ETH.mul(THOUSAND), ONE_ETH.mul(TEN));
            await mainInstance.forceSync();
                
            await mainInstance.connect(owner).enableClaims();

            // make synthetic  situation when totalCumulativeAmount are small
            await mainInstance.connect(owner).setTotalCumulativeClaimed(ONE);
            await expect(
                mainInstance.connect(owner).claim(ONE, bob.address)
            ).to.be.revertedWith("ClaimValidationError()");
        });             

        describe("presale", function () {
            var Presale;
            let ts, timeUntil;

            beforeEach("before", async() => {
                ts = await time.latest();
                timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
                const PresaleF = await ethers.getContractFactory("PresaleMock");
                Presale = await PresaleF.deploy();
            });

            it("shouldnt presale if caller is not owner", async() => {
                
                await expect(
                    mainInstance.connect(bob).startPresale(Presale.address, ONE_ETH, timeUntil)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });
 
            it("should burn after presale end", async() => {
                
                // make snapshot before time manipulations
                const snapId = await ethers.provider.send('evm_snapshot', []);
                //console.log("make snapshot");
                
                await Presale.setEndTime(timeUntil);

                const tokenBefore = await mainInstance.balanceOf(Presale.address);
                await mainInstance.connect(owner).startPresale(Presale.address, ONE_ETH, DAY);
                const tokenAfter = await mainInstance.balanceOf(Presale.address);

                expect(tokenBefore).to.be.eq(ZERO);
                expect(tokenAfter).to.be.eq(ONE_ETH);
                
                // can be burn in the end( before an hour the endTime)
                await mainInstance.connect(owner).burnRemaining(Presale.address);
                const tokenAfter2 = await mainInstance.balanceOf(Presale.address);
                expect(tokenAfter2).to.be.eq(tokenAfter);

                // pass in the end
                await network.provider.send("evm_increaseTime", [parseInt(lockupIntervalAmount*DAY)]);
                await network.provider.send("evm_mine");

                const tokenBefore3 = await mainInstance.balanceOf(Presale.address);
                await mainInstance.connect(owner).burnRemaining(Presale.address);
                const tokenAfter3 = await mainInstance.balanceOf(Presale.address);

                expect(tokenBefore3).to.be.eq(ONE_ETH);
                expect(tokenAfter3).to.be.eq(ZERO);

                // also try to burn after burning)
                await mainInstance.connect(owner).burnRemaining(Presale.address);
                const tokenAfter4 = await mainInstance.balanceOf(Presale.address);
                expect(tokenAfter4).to.be.eq(ZERO);

                // restore snapshot
                await ethers.provider.send('evm_revert', [snapId]);
                //console.log("revert to snapshot");
            });

            
            it("should presale", async() => {
                
                const snapId = await ethers.provider.send('evm_snapshot', []);

                await Presale.setEndTime(timeUntil);

                //const tokenBefore = await mainInstance.balanceOf(Presale.address);
                await mainInstance.connect(owner).startPresale(Presale.address, ONE_ETH, lockupIntervalDay);

                const amountSend = ONE_ETH.div(TEN);
                const lockedBefore = await mainInstance.getLockedAmount(bob.address);
                const lockedPresaleBefore = await mainInstance.getLockedAmount(Presale.address);

                // imitation presale operations
                let tx = await Presale.transferTokens(mainInstance.address, bob.address, amountSend);

                const lockedAfter = await mainInstance.getLockedAmount(bob.address);
                const lockedPresaleAfter = await mainInstance.getLockedAmount(Presale.address);

                const rc = await tx.wait();
                const block = await web3.eth.getBlock(rc.blockNumber);
                const startts = Math.floor(block.timestamp/DAY)*DAY;
                const timePassed = block.timestamp - startts;
                const speed = amountSend.div(lockupIntervalDay*DAY);
                const expectLocked = amountSend.sub(speed.mul(timePassed));
                
                expect(lockedBefore).to.be.eq(ZERO);
                expect(lockedPresaleBefore).to.be.eq(ZERO);
                expect(lockedPresaleAfter).to.be.eq(ZERO);

                // floating point in js. So didnt check last six digits/ for the numbers like below
                // lockedAfter = BigNumber.from('53031249999981333');
                // expectLocked = BigNumber.from('53031250000016533');

                expect(
                    Math.round(lockedAfter/1000000)*1000000
                ).to.be.eq(
                    Math.round(expectLocked/1000000)*1000000
                );

                await ethers.provider.send('evm_revert', [snapId]);
            });
            // it("", async() => {});

            describe("shouldnt presale if Presale contract invalid", function () {
                it(" --- zero address", async() => {
                    await expect(
                        mainInstance.connect(owner).startPresale(ZERO_ADDRESS, ONE_ETH, timeUntil)
                    ).to.be.revertedWith('Transaction reverted: function returned an unexpected amount of data');
                });
                it(" --- eoa address", async() => {
                    await expect(
                        mainInstance.connect(owner).startPresale(bob.address, ONE_ETH, timeUntil)
                    ).to.be.revertedWith('Transaction reverted: function returned an unexpected amount of data');
                });
                it(" --- without endTime method", async() => {
                    const PresaleBad1F = await ethers.getContractFactory("PresaleBad1");
                    let presaleBad1 = await PresaleBad1F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad1.address, ONE_ETH, timeUntil)
                    ).to.be.revertedWith("Transaction reverted: function selector was not recognized and there's no fallback function");
                });
                xit(" --- endTime have wrong output", async() => {
                    const PresaleBad2F = await ethers.getContractFactory("PresaleBad2");
                    let presaleBad2 = await PresaleBad2F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad2.address, ONE_ETH, timeUntil)
                    ).to.be.revertedWith("Transaction reverted: function selector was not recognized and there's no fallback function");
                });
                it(" --- fallback method only", async() => {
                    const PresaleBad3F = await ethers.getContractFactory("PresaleBad3");
                    let presaleBad3 = await PresaleBad3F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad3.address, ONE_ETH, timeUntil)
                    ).to.be.revertedWith('Transaction reverted: function returned an unexpected amount of data');
                });
                // it(" --- without wrong signature endTime", async() => {});
                
            });
           
        }); 

        describe("claim", function () {
            beforeEach("adding liquidity", async() => {

                await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));

                // let uniswapV2Pair = await mainInstance.uniswapV2Pair();
                // pair = await ethers.getContractAt("IUniswapV2Pair",uniswapV2Pair);
                // let tmp;
                // tmp = await pair.getReserves();
                // console.log("js::pair:price0CumulativeLast(1) = ", await pair.price0CumulativeLast());  
                // console.log("js::pair:blockTimestampLast = ", tmp[2]);  
                // console.log("js   addInitialLiquidity ");  
                
                await expect(
                    mainInstance.connect(owner).addLiquidity(ONE_ETH)
                ).to.be.revertedWith("InitialLiquidityRequired()");

                await expect(
                    mainInstance.connect(charlie).addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN))
                ).to.be.revertedWith("OwnerAndManagersOnly()");

                await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));
                await expect(
                    mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN))
                ).to.be.revertedWith("AlreadyCalled()");

                // tmp = await pair.getReserves();
                // console.log("js::pair:price0CumulativeLast(1) = ", await pair.price0CumulativeLast());  
                // console.log("js::pair:blockTimestampLast = ", tmp[2]);  

                //await pair.sync();
                await mainInstance.forceSync();
                // console.log("js::pair:price0CumulativeLast(2) = ", await pair.price0CumulativeLast());
                // tmp = await pair.getReserves();
                // console.log("js::pair:blockTimestampLast = ", tmp[2]);  
                // //let t_recipe = await t.wait();
                // //for (let i =0; i<t_recipe.events; i++) {}
                // //console.log(t_recipe.events);

                // await expect(
                //     mainInstance.connect(owner).addLiquidity(ONE_ETH)
                // ).to.be.revertedWith("maxAddLiquidity exceeded");
                //"MISSING_HISTORICAL_OBSERVATION"
                
            });

            
            it("shouldnt presale already added liquidity", async() => {
                let ts = await time.latest();
                let timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
                await expect(
                    mainInstance.connect(owner).startPresale(alice.address, ONE_ETH, timeUntil)
                ).to.be.revertedWith("BeforeInitialLiquidityRequired()");
            });

            it("[cover] available to claim == 0", async() => {
                await mainInstance.connect(owner).setRestrictClaiming([ONE_ETH, 1]);
                
                let availableToClaim = await mainInstance.availableToClaim();
                expect(availableToClaim).to.be.eq(ZERO);
            });


            it("shouldnt claim if claimingTokenAmount == 0", async() => {

                await expect(
                    claimManager.connect(bob).claim(ZERO, bob.address)
                ).to.be.revertedWith("InputAmountCanNotBeZero()");

                // by owner
                await mainInstance.connect(owner).enableClaims();
                await expect(
                    mainInstance.connect(owner).claim(ZERO, owner.address)
                ).to.be.revertedWith("InputAmountCanNotBeZero()");
            });

            it("shouldnt claim with empty address", async() => {
                await mainInstance.connect(owner).enableClaims();
                await expect(
                    mainInstance.connect(owner).claim(ONE_ETH, ZERO_ADDRESS)
                ).to.be.revertedWith("EmptyAccountAddress()");
            });

            it("shouldnt call restrictClaiming by owner", async() => {
                await expect(
                    mainInstance.connect(owner).restrictClaiming([ONE_ETH, 1])
                ).to.be.revertedWith("ManagersOnly()");
            });

            it("shouldnt setup zero denominator", async() => {
                await expect(
                    mainInstance.connect(bob).restrictClaiming([ONE_ETH, 1])
                ).to.be.revertedWith("ManagersOnly()");

                await mainInstance.connect(owner).addManager(bob.address);
                await expect(
                    mainInstance.connect(bob).restrictClaiming([ONE_ETH, 0])
                ).to.be.revertedWith("ZeroDenominator()");
            });

            

            it("shouldnt price grow too fast", async() => {
                await mainInstance.connect(owner).addManager(bob.address);
                await expect(
                    mainInstance.connect(bob).restrictClaiming([ONE, HUN])
                ).to.be.revertedWith("MinClaimPriceGrowTooFast()");
            });

            it("shouldnt price less than setup before", async() => {
                await mainInstance.connect(owner).addManager(bob.address);

                let minClaimPriceUpdatedTime = await mainInstance.getMinClaimPriceUpdatedTime();
                
                await network.provider.send("evm_increaseTime", [parseInt(minClaimPriceUpdatedTime)]);
                await network.provider.send("evm_mine");

                await expect(
                    mainInstance.connect(bob).restrictClaiming([minClaimPriceNumerator, minClaimPriceDenominator+1])
                ).to.be.revertedWith("ShouldBeMoreThanMinClaimPrice()");
            });

            
            describe("some validate", function () {
                const tokensToClaim = THOUSAND.mul(ONE_ETH);

                beforeEach("before", async() => {
               
                    await externalToken.connect(owner).mint(charlie.address, tokensToClaim);
                    await externalToken.connect(charlie).approve(claimManager.address, tokensToClaim);
                    await claimManager.connect(charlie).wantToClaim(tokensToClaim);
                    // pass time to clear bucket
                    await network.provider.send("evm_increaseTime", [claimFrequency]);
                    await network.provider.send("evm_mine");

                    await mainInstance.connect(owner).addManager(claimManager.address);
                });

                    
                it("price has not become a lower than minClaimPrice ", async() => {
                    await mainInstance.connect(owner).enableClaims();
                    await expect(
                        claimManager.connect(charlie).claim(tokensToClaim, bob.address)
                    ).to.be.revertedWith("PriceHasBecomeALowerThanMinClaimPrice()");
                });

                it("shouldnt claim if claimTime == 0 (disabled)", async() => {
                    await expect(
                        claimManager.connect(charlie).claim(tokensToClaim, bob.address)
                    ).to.be.revertedWith("ClaimsDisabled()");
                });
            });

            describe("mint and approve", function () {
                beforeEach("minting to bob and approve", async() => {
                    await mainInstance.connect(owner).enableClaims();

                    await externalToken.connect(owner).mint(bob.address, ONE_ETH);
                    await externalToken.connect(bob).approve(claimManager.address, ONE_ETH);
                });

                it("shouldnt claim if claimingTokenAmount more than allowance", async() => {
                    await expect(
                        claimManager.connect(bob).claim(ONE_ETH.add(ONE_ETH), bob.address)
                    ).to.be.revertedWith("InsufficientAmount()");
                });
                
                it("shouldnt wantToClaim if amount more that available", async() => {
                    await expect(
                        claimManager.connect(bob).wantToClaim(HUN.mul(ONE_ETH))
                    ).to.be.revertedWith(`InsufficientAmount()`);
                });

                it("shouldnt claim too fast", async() => {

                    const lastActionTs = await claimManager.getLastActionTime(bob.address);
                    await expect(
                        claimManager.connect(bob).claim(ONE_ETH, bob.address)
                    ).to.be.revertedWith(`ClaimTooFast(${lastActionTs.add(claimFrequency)})`);
                });   

                
                it("shouldnt claim if didnt wantClaim before", async() => {
                    // pass time to clear bucket
                    await network.provider.send("evm_increaseTime", [claimFrequency]);
                    await network.provider.send("evm_mine");

                    await expect(
                        claimManager.connect(bob).claim(ONE_ETH, bob.address)
                    ).to.be.revertedWith(`InsufficientAmountToClaim(${ONE_ETH}, ${ZERO})`);
                });


                describe("call wantToClaim", function () {
                    
                    beforeEach("before", async() => {
                        //await claimManager.connect(bob).wantToClaim(ONE_ETH);
                        await claimManager.connect(bob).wantToClaim(ZERO); // all awailable
                        // pass time 
                        await network.provider.send("evm_increaseTime", [claimFrequency]);
                        await network.provider.send("evm_mine");
                    });

                    it("shouldnt claim if claimManager is not a manager for TradedToken ", async() => {
                        await expect(
                            claimManager.connect(bob).claim(ONE_ETH, bob.address)
                        ).to.be.revertedWith(`OwnerAndManagersOnly()`);
    
                    });

                    describe("make claimManager as a manager", function () {
                        beforeEach("before", async() => {
                            //await claimManager.connect(bob).wantToClaim(ONE_ETH);
                            await mainInstance.connect(owner).addManager(claimManager.address);
                        });
                        
                        it("should claim", async() => {
                            await claimManager.connect(bob).claim(ONE_ETH, bob.address);
                        });

                        it("should transfer to dead-address tokens after user claim", async() => {
                            const tokensToClaim = ONE_ETH;
                            const tokensBefore = await externalToken.balanceOf(DEAD_ADDRESS);
                            await claimManager.connect(bob).claim(tokensToClaim, bob.address);
                            const tokensAfter = await externalToken.balanceOf(DEAD_ADDRESS);
                            expect(tokensBefore.add(tokensToClaim)).to.be.eq(tokensAfter);
                        });

                        it("should claim (scale 1:2 applying) ", async() => {

                            //let snapId = await ethers.provider.send('evm_snapshot', []);

                            
                            let availableToClaim = await mainInstance.availableToClaim();

                            let userWantToClaim = ONE_ETH; 
                            //await externalToken.connect(owner).mint(bob.address, userWantToClaim);
                            await externalToken.connect(owner).mint(charlie.address, availableToClaim.mul(TWO));
                            await externalToken.connect(charlie).approve(claimManager.address, availableToClaim.mul(TWO));

                            let bobExternalTokenBalanceBefore = await externalToken.balanceOf(bob.address);
                            let mainInstanceExternalTokenBalanceBefore = await externalToken.balanceOf(mainInstance.address);

                            // two users want to get all available amount of tokens
                            let wantToClaimTotal = ZERO;
                            await claimManager.connect(bob).wantToClaim(userWantToClaim);
                            wantToClaimTotal = wantToClaimTotal.add(userWantToClaim);
                            await claimManager.connect(charlie).wantToClaim(availableToClaim.mul(TWO));
                            wantToClaimTotal = wantToClaimTotal.add(availableToClaim.mul(TWO));

                            // pass time 
                            await network.provider.send("evm_increaseTime", [claimFrequency]);
                            await network.provider.send("evm_mine");

                            await expect(
                                claimManager.connect(bob).claim(userWantToClaim, bob.address)
                            ).to.be.revertedWith(`InsufficientAmountToClaim(${userWantToClaim}, ${userWantToClaim.mul(availableToClaim).div(wantToClaimTotal)})`);

                            let scaledAmount = userWantToClaim.mul(availableToClaim).div(wantToClaimTotal);
                            await claimManager.connect(bob).claim(scaledAmount, bob.address);

                            let bobExternalTokenBalanceAfter = await externalToken.balanceOf(bob.address);
                            let mainInstanceExternalTokenBalanceAfter = await externalToken.balanceOf(mainInstance.address);

                            expect(await mainInstance.balanceOf(bob.address)).to.be.eq(scaledAmount);
                            expect(bobExternalTokenBalanceBefore.sub(bobExternalTokenBalanceAfter)).to.be.eq(scaledAmount);
                            expect(mainInstanceExternalTokenBalanceAfter.sub(mainInstanceExternalTokenBalanceBefore)).to.be.eq(ZERO);

                            //await ethers.provider.send('evm_revert', [snapId]);
                        });
                        
                    });
                });

                

            });
            
            describe("internal", function () {
                const AmountToClaim = ONE_ETH.mul(HUN);
                before("make snapshot", async() => {
                    // make snapshot before time manipulations
                    snapId = await ethers.provider.send('evm_snapshot', []);
                    //console.log("make snapshot");
                });

                after("revert to snapshot", async() => {
                    // restore snapshot
                    await ethers.provider.send('evm_revert', [snapId]);
                    //console.log("revert to snapshot");
                });

                beforeEach("before", async() => {
                    await mainInstance.connect(owner).enableClaims();
                });

                
 
                it("shouldnt locked up tokens after owner claim", async() => {

                    const bobTokensBefore = await mainInstance.balanceOf(bob.address);
                    const aliceTokensBefore = await mainInstance.balanceOf(alice.address);

                    await mainInstance.connect(owner).claim(ONE_ETH, owner.address);

                    await mainInstance.connect(owner).transfer(alice.address,ONE_ETH);

                    await mainInstance.connect(owner).claim(ONE_ETH, bob.address);

                    const bobTokensAfterClaim = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterClaim = await mainInstance.balanceOf(alice.address);

                    expect(bobTokensAfterClaim.sub(bobTokensBefore)).to.be.eq(ONE_ETH);
                    expect(aliceTokensAfterClaim.sub(aliceTokensBefore)).to.be.eq(ONE_ETH);

                    await mainInstance.connect(bob).transfer(alice.address,ONE_ETH)

                    const bobTokensAfterTransfer = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterTransfer = await mainInstance.balanceOf(alice.address);

                    expect(bobTokensAfterTransfer.sub(bobTokensBefore)).to.be.eq(ZERO);
                    expect(aliceTokensAfterTransfer.sub(aliceTokensAfterClaim)).to.be.eq(ONE_ETH);

                }); 

                it("shouldnt exceed holdersMax", async() => {

                    await mainInstance.connect(owner).claim(ONE_ETH.mul(TEN), owner.address);

                    await mainInstance.connect(owner).transfer(bob.address,ONE_ETH);
                    await mainInstance.connect(owner).transfer(alice.address,ONE_ETH);

                    await mainInstance.setHoldersMax(ONE);

                    await expect(
                        mainInstance.connect(owner).transfer(charlie.address,ONE_ETH)
                    ).to.be.revertedWith(`MaxHoldersCountExceeded(${ONE})`);
                    
                });

                it("shouldn't _preventPanic when transfer", async() => {
                    // make a test when Bob can send to Alice only 50% of their tokens through a day

                    const InitialSendFunds = ONE_ETH;
                    const bobTokensBefore = await mainInstance.balanceOf(bob.address);
                    const aliceTokensBefore = await mainInstance.balanceOf(alice.address);

                    await mainInstance.connect(owner).claim(InitialSendFunds, bob.address);

                    const bobTokensAfterClaim = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterClaim = await mainInstance.balanceOf(alice.address);

                    expect(bobTokensAfterClaim.sub(bobTokensBefore)).to.be.eq(InitialSendFunds);
                    expect(aliceTokensAfterClaim.sub(aliceTokensBefore)).to.be.eq(ZERO);
                    
                    const DurationForAlice = 24*60*60; // day
                    const RateForAlice = 5000; // 50%
                    const smthFromOwner= 1;
                    await mainInstance.connect(owner).setRateLimit([DurationForAlice, RateForAlice])

                    // can't send tokens to new members before owner put him into whitelist(will transfer some tokens to him)
                    await expect(
                        mainInstance.connect(bob).transfer(alice.address, bobTokensAfterClaim)
                    ).to.be.revertedWith("OwnerAndManagersOnly()");
                    
                    // send a little
                    await mainInstance.connect(owner).claim(smthFromOwner, alice.address);
                    
                    // now will be ok
                    await mainInstance.connect(bob).transfer(alice.address, bobTokensAfterClaim);

                    const bobTokensAfterTransfer = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterTransfer = await mainInstance.balanceOf(alice.address);

                    //expect(bobTokensAfterClaim.mul(RateForAlice).div(FRACTION)).to.be.eq(bobTokensAfterTransfer);
                    //expect(bobTokensAfterClaim.add(smthFromOwner).sub(bobTokensAfterClaim.mul(RateForAlice).div(FRACTION))).to.be.eq(aliceTokensAfterTransfer);
                    expect(bobTokensAfterTransfer).to.be.eq(ZERO);
                    expect(bobTokensAfterClaim.add(smthFromOwner)).to.be.eq(aliceTokensAfterTransfer);
                    

                    // try to send all that left
                    let tx = await mainInstance.connect(bob).transfer(alice.address, bobTokensAfterTransfer)
                    
                    const bobTokensAfterTransfer2 = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterTransfer2 = await mainInstance.balanceOf(alice.address);
                    let rc = await tx.wait();
                        
                    // here fast and stupid way to find event PanicSellRateExceeded that cann't decoded if happens in external contract
                    let arr2compare = [
                        ethers.utils.id("PanicSellRateExceeded(address,address,uint256)"), // keccak256
                        '0x'+(bob.address.replace('0x','')).padStart(64, '0'),
                        '0x'+(alice.address.replace('0x','')).padStart(64, '0')
                    ]
                    let event = rc.events.find(event => JSON.stringify(JSON.stringify(event.topics)).toLowerCase() === JSON.stringify(JSON.stringify(arr2compare)).toLowerCase());
                    let eventExists = (typeof(event) !== 'undefined') ? true : false;

                    expect(eventExists).to.be.eq(false);
                    //expect(eventExists).to.be.eq(true);
                    /*
                    if (eventExists) {
                        // address: '0x2d13826359803522cCe7a4Cfa2c1b582303DD0B4',
                        // topics: [
                        //     '0xda8c6cfc61f9766da27a11e69038df366444016f44f525a2907f393407bfc6c3',
                        //     '0x00000000000000000000000090f79bf6eb2c4f870365e785982e1f101e93b906',
                        //     '0x0000000000000000000000009b7889734ac75060202410362212d365e9ee1ef5'
                        // ],
                        expect(event.address).to.be.eq(mainInstance.address);
                        expect(ethers.utils.getAddress( event.topics[1].replace('000000000000000000000000','') )).to.be.eq(bob.address);
                        expect(ethers.utils.getAddress( event.topics[2].replace('000000000000000000000000','') )).to.be.eq(alice.address);

                        // we will adjust value in panic situation from amount to 5
                        // so transaction didn't revert but emitted event "PanicSellRateExceeded"

                        expect(bobTokensAfterTransfer.sub(5)).to.be.eq(bobTokensAfterTransfer2);
                        expect(aliceTokensAfterTransfer.add(5)).to.be.eq(aliceTokensAfterTransfer2);
                    }

                    // pass time to clear bucket
                    await network.provider.send("evm_increaseTime", [DurationForAlice+50]);
                    await network.provider.send("evm_mine");

                    const bobTokensBeforeTransferAndTimePassed = await mainInstance.balanceOf(bob.address);
                    const aliceTokensBeforeTransferAndTimePassed = await mainInstance.balanceOf(alice.address);

                    await mainInstance.connect(bob).transfer(alice.address, bobTokensBeforeTransferAndTimePassed);

                    const bobTokensAfterTransferAndTimePassed = await mainInstance.balanceOf(bob.address);
                    const aliceTokensAfterTransferAndTimePassed = await mainInstance.balanceOf(alice.address);
                    
                    //----------------------

                    // console.log("bobTokensBeforeTransferAndTimePassed   = ", bobTokensBeforeTransferAndTimePassed.toString());
                    // console.log("bobTokensAfterTransferAndTimePassed    = ", bobTokensAfterTransferAndTimePassed.toString());
                    // console.log(" -------------------------------- ");
                    // console.log("aliceTokensBeforeTransferAndTimePassed = ", aliceTokensBeforeTransferAndTimePassed.toString());
                    // console.log("aliceTokensAfterTransferAndTimePassed  = ", aliceTokensAfterTransferAndTimePassed.toString());
                    
                    expect(bobTokensBeforeTransferAndTimePassed.mul(RateForAlice).div(FRACTION).add(ONE)).to.be.eq(bobTokensAfterTransferAndTimePassed);
                    expect(aliceTokensBeforeTransferAndTimePassed.add(bobTokensBeforeTransferAndTimePassed.sub(ONE).sub(bobTokensBeforeTransferAndTimePassed.mul(RateForAlice).div(FRACTION)))).to.be.eq(aliceTokensAfterTransferAndTimePassed);
                    */


                        
                }); 

                it("shouldnt locked up tokens if owner claim to himself", async() => {
                    await mainInstance.connect(owner).claim(ONE_ETH, owner.address);
                    expect(await mainInstance.balanceOf(owner.address)).to.be.eq(ONE_ETH);

                    await mainInstance.connect(owner).transfer(alice.address,ONE_ETH);
                    expect(await mainInstance.balanceOf(alice.address)).to.be.eq(ONE_ETH);

                    const smthFromOwner= 1;
                    // can't send tokens to new members before owner put him into whitelist(will transfer some tokens to him)
                    await expect(
                        mainInstance.connect(alice).transfer(bob.address,ONE_ETH)
                    ).to.be.revertedWith("OwnerAndManagersOnly()");
                    
                    // send a little
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
                    
                    // now will be ok
                    await mainInstance.connect(alice).transfer(bob.address,ONE_ETH);
                    expect(await mainInstance.balanceOf(bob.address)).to.be.eq(ONE_ETH.add(smthFromOwner));
                    
                }); 

                it("should locked up tokens", async() => {
                    const smthFromOwner= 1;
                    // send a little
                    await mainInstance.connect(owner).claim(smthFromOwner, charlie.address);

                    await mainInstance.connect(owner).addManager(bob.address);
                    await mainInstance.connect(bob).claim(ONE_ETH, bob.address);
                    
                    await expect(mainInstance.connect(bob).transfer(charlie.address,ONE_ETH)).to.be.revertedWith("InsufficientAmount()");
                }); 

            }); 

        });

        describe("uniswap settings", function () {
            var uniswapRouterFactoryInstance, uniswapRouterInstance, pairInstance;
            var printTotalInfo = async () => {
                return; 
                let r0, r1, blockTimestamp, price0Cumulative, price1Cumulative, timestampLast, price0CumulativeLast, price0Average;
                [r0, r1, blockTimestamp, price0Cumulative, price1Cumulative, timestampLast, price0CumulativeLast, price0Average] = await mainInstance.connect(owner).totalInfo();
                let maxAddLiquidityR0, maxAddLiquidityR1;
                [maxAddLiquidityR0, maxAddLiquidityR1] = await mainInstance.connect(owner).maxAddLiquidity();
                console.log(" ============== totalInfo ============== ");
                console.log("r0                  = ", r0.toString());
                console.log("r1                  = ", r1.toString());
                console.log("blockTimestamp      = ", blockTimestamp.toString());
                console.log("         ------ observed --------         ");
                console.log("price0Cumulative    = ", price0Cumulative.toString());
                console.log("price1Cumulative    = ", price1Cumulative.toString());
                console.log("timestampLast       = ", timestampLast.toString());
                console.log("price0CumulativeLast= ", price0CumulativeLast.toString());
                console.log("price0Average       = ", price0Average.toString());
                console.log("      ------ max liquidity --------      ");
                console.log("maxAddLiquidityR0       = ", maxAddLiquidityR0.toString());
                console.log("maxAddLiquidityR1       = ", maxAddLiquidityR1.toString());
                console.log(" --------------------------------------  ");

                
            };
            beforeEach("adding liquidity", async() => {

                await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));
                
                await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));
                //await mainInstance.forceSync();
                
                //await printTotalInfo();
                
                //uniswapRouterFactoryInstance = await ethers.getContractAt("IUniswapV2Factory",UNISWAP_ROUTER_FACTORY_ADDRESS);
                uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

                

            });

            it("shouldnt swap if owner send the tokens before", async() => {
                let ts, timeUntil;
            
                await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
                ts = await time.latest();
                timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
                
                await expect(uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ONE_ETH.div(2), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                )).to.be.revertedWith('UniswapV2: TRANSFER_FAILED'); // reverted in TradedToken with "OwnerAndManagersOnly()"
            });

            describe("taxes", function () {
                var storedBuyTax, storedSellTax;
                beforeEach("before", async() => {
                    storedBuyTax = await mainInstance.buyTax();
                    storedSellTax = await mainInstance.sellTax();
                }); 

                it("should setup buyTaxMax and sellTaxMax when deploy", async() => {
                    expect(await mainInstance.buyTaxMax()).to.be.equal(maxBuyTax);
                    expect(await mainInstance.sellTaxMax()).to.be.equal(maxSellTax);
                }); 

                it("should sellTax and buyTax to be zero when deploy", async() => {
                    expect(storedBuyTax).to.be.equal(ZERO);
                    expect(storedSellTax).to.be.equal(ZERO);
                }); 

                it("shouldt setup buyTax value more then buyTaxMax", async() => {
                    await expect(mainInstance.setTaxes(maxBuyTax.add(ONE), storedSellTax)).to.be.revertedWith(`TaxesTooHigh()`);
                }); 

                it("shouldt setup sellTax value more then sellTaxMax", async() => {
                    await expect(mainInstance.setTaxes(storedBuyTax, maxSellTax.add(ONE))).to.be.revertedWith(`TaxesTooHigh()`);
                }); 
                
                it("should setup sellTax", async() => {
                    const oldValue = storedSellTax;

                    const value = maxSellTax.sub(ONE);
                    await mainInstance.setTaxes(storedBuyTax, value);

                    const newValue = await mainInstance.sellTax();
                    
                    expect(oldValue).not.to.be.eq(newValue);
                    expect(value).to.be.eq(newValue);
                }); 

                it("should setup buyTax", async() => {
                    const oldValue = storedBuyTax;

                    const value = maxBuyTax.sub(ONE);
                    await mainInstance.setTaxes(value, storedSellTax);

                    const newValue = await mainInstance.buyTax();

                    expect(oldValue).not.to.be.eq(newValue);
                    expect(value).to.be.eq(newValue);
                }); 

                it("should setup sellTax gradually", async() => {
                    await mainInstance.setTaxesInfoInit([1000,1000,true,true]);
                    const oldValue = await mainInstance.sellTax();

                    const value = maxSellTax.sub(ONE);
                    await mainInstance.setTaxes(storedBuyTax, value);

                    const newValueStart = await mainInstance.sellTax();
                    
                    await network.provider.send("evm_increaseTime", [500]);
                    await network.provider.send("evm_mine");

                    const newValueHalf = await mainInstance.sellTax();

                    await network.provider.send("evm_increaseTime", [10000]);
                    await network.provider.send("evm_mine");

                    const newValueOverFinal = await mainInstance.sellTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.lt(newValueHalf);
                    expect(newValueHalf).to.be.lt(newValueOverFinal);
                    expect(value).to.be.eq(newValueOverFinal);

                }); 

                it("should setup buyTax gradually", async() => {
                    await mainInstance.setTaxesInfoInit([1000,1000,true,true]);
                    const oldValue = await mainInstance.buyTax();

                    const value = maxBuyTax.sub(ONE);
                    await mainInstance.setTaxes(value, storedSellTax);

                    const newValueStart = await mainInstance.buyTax();

                    await network.provider.send("evm_increaseTime", [500]);
                    await network.provider.send("evm_mine");

                    const newValueHalf = await mainInstance.buyTax();

                    await network.provider.send("evm_increaseTime", [10000]);
                    await network.provider.send("evm_mine");

                    const newValueOverFinal = await mainInstance.buyTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.lt(newValueHalf);
                    expect(newValueHalf).to.be.lt(newValueOverFinal);
                    expect(value).to.be.eq(newValueOverFinal);

                }); 

                it("should setup buyTax gradually down", async() => {
                    
                    const value = maxBuyTax.sub(ONE);

                    await mainInstance.setTaxes(value, storedSellTax);
                    const oldValue = await mainInstance.buyTax();

                    await mainInstance.setTaxesInfoInit([1000,1000,true,true]);
                    // to make setup fromTax as `maxBuyTax.sub(ONE)` need to pass full time duration. 
                    // if call setTax in the middle of period then contract will calculate taxFrom as (from+to)/2
                    await network.provider.send("evm_increaseTime", [10000]);
                    await network.provider.send("evm_mine");
                    //----------------------------------

                    const value2 = ONE;

                    await mainInstance.setTaxes(value2, storedSellTax);

                    const newValueStart = await mainInstance.buyTax();

                    await network.provider.send("evm_increaseTime", [500]);
                    await network.provider.send("evm_mine");

                    const newValueHalf = await mainInstance.buyTax();

                    await network.provider.send("evm_increaseTime", [10000]);
                    await network.provider.send("evm_mine");

                    const newValueOverFinal = await mainInstance.buyTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.gt(newValueHalf);
                    expect(newValueHalf).to.be.gt(newValueOverFinal);
                    expect(value2).to.be.eq(newValueOverFinal);

                }); 

                it("should burn buyTax", async() => {

                    await mainInstance.connect(owner).enableClaims();
                
                    let ts, timeUntil;
                    
                    // make snapshot
                    // make swapExactTokensForTokens  without tax
                    // got amount that user obtain
                    // restore snapshot
                    // setup buy tax and the same swapExactTokensForTokens as previous
                    // obtained amount should be less by buytax
                    //---------------------------
                    var snapId = await ethers.provider.send('evm_snapshot', []);

                    await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let bobBalanceBeforeWoTax = await mainInstance.balanceOf(bob.address);
                    const smthFromOwner = 1;
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ONE_ETH.div(2), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    
                    let bobBalanceAfterWoTax = await mainInstance.balanceOf(bob.address);

                    await ethers.provider.send('evm_revert', [snapId]);
                    //----

                    const tax = FRACTION.mul(10).div(100);
                    
                    await mainInstance.setTaxes(tax, storedSellTax);

                    await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let bobBalanceBeforeWithTax = await mainInstance.balanceOf(bob.address);
                    
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ONE_ETH.div(2), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWithTax = await mainInstance.balanceOf(bob.address);
                    //-----

                    // now check
                    let deltaWithTax = bobBalanceAfterWithTax.sub(bobBalanceBeforeWithTax);
                    let deltaWWoTax = bobBalanceAfterWoTax.sub(bobBalanceBeforeWoTax);

                    expect(deltaWithTax).not.be.eq(deltaWWoTax);
                    expect(deltaWithTax).not.be.eq(deltaWWoTax.mul(tax).div(FRACTION));

                });

                it("should burn sellTax", async() => {
    
                    await mainInstance.connect(owner).enableClaims();

                    let ts, timeUntil;
                    uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

                    // make swapExactTokensForTokens  without tax to obtain tradedToken
                    // make snapshot
                    // make swapExactTokensForTokens  without tax
                    // got amount that user obtain
                    // restore snapshot
                    // setup buy tax and the same swapExactTokensForTokens as previous
                    // obtained amount should be less by buytax
                    //---------------------------
                    await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let tmp = await mainInstance.balanceOf(bob.address);
                    const smthFromOwner = 1;
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ONE_ETH.div(2), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );

                    let tmp2 = await mainInstance.balanceOf(bob.address);
                    const obtainERC777Tokens = tmp2.sub(tmp);
                    //----
                    var snapId = await ethers.provider.send('evm_snapshot', []);

                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let bobBalanceBeforeWoTax = await erc20ReservedToken.balanceOf(bob.address);

                    await mainInstance.connect(bob).approve(uniswapRouterInstance.address, obtainERC777Tokens);
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        obtainERC777Tokens, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWoTax = await erc20ReservedToken.balanceOf(bob.address);

                    await ethers.provider.send('evm_revert', [snapId]);
                    //----

                    const tax = FRACTION.mul(10).div(100);
                    
                    await mainInstance.setTaxes(storedBuyTax, tax);

                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let bobBalanceBeforeWithTax = await erc20ReservedToken.balanceOf(bob.address);

                    await mainInstance.connect(bob).approve(uniswapRouterInstance.address, obtainERC777Tokens);
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        obtainERC777Tokens, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWithTax = await erc20ReservedToken.balanceOf(bob.address);
                    //-----

                    // now check
                    let deltaWithTax = bobBalanceAfterWithTax.sub(bobBalanceBeforeWithTax);
                    let deltaWWoTax = bobBalanceAfterWoTax.sub(bobBalanceBeforeWoTax);

                    expect(deltaWithTax).not.be.eq(deltaWWoTax);
                    expect(deltaWithTax).not.be.eq(deltaWWoTax.mul(tax).div(FRACTION));

                });
            }); 

            describe("with first swap", function () {
                beforeEach("prepare", async() => {
                    /////////////////////////////
                
                    await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
                    let ts = await time.latest();
                    let timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    
                    await expect(uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ONE_ETH.div(2), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   


                    )).to.be.revertedWith('UniswapV2: TRANSFER_FAILED'); // reverted in TradedToken with "OwnerAndManagersOnly()"

                    const smthFromOwner = 1;
                    await mainInstance.connect(owner).enableClaims();
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ONE_ETH.div(2), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );

                    await printTotalInfo();

                    /////////////////////////////
                });

                
                describe("Adding liquidity. synth", function () {
                    var snapId;
                    var internalLiquidityAddress;
                    beforeEach("make snapshot", async() => {
                        // make snapshot before time manipulations
                        snapId = await ethers.provider.send('evm_snapshot', []);
                        internalLiquidityAddress = await mainInstance.getInternalLiquidity();
                    });

                    afterEach("revert to snapshot", async() => {
                        // restore snapshot
                        await ethers.provider.send('evm_revert', [snapId]);
                    });

                    it("synth case: try to get stored average price", async() => {

                        let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                        [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                        maxliquidity = tradedReserve2.sub(tradedReserve1);

                        add2Liquidity = maxliquidity.abs().mul(1).div(1000);

                        await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                        await ethers.provider.send('evm_increaseTime', [5]);
                        await ethers.provider.send('evm_mine');
                        await mainInstance.connect(owner).addLiquidity(add2Liquidity);

                     //   expect(t).to.be.eq(t2);

                    });

                    it("should add liquidity. liquidity contract middleware shouldn't have funds left after added liquidity", async() => {
                        
                        let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                        [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                        maxliquidity = tradedReserve2.sub(tradedReserve1);

                        add2Liquidity = maxliquidity.abs().mul(1).div(1000);

                        // math presicion!!!  left can be like values less then 10
                        expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                        expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                        // adding liquidity
                        await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                        // shouldn't have any tokens left on middleware
                        expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                        expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                        // and again
                        await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                        expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                        expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(TEN);
                    });

                    it("should _preventPanic", async() => {

                        const uniswapV2Pair = await mainInstance.uniswapV2Pair();

                        const DurationForUniswap = 24*60*60; // day
                        const RateForUniswap = 5000; // 50%
                        await mainInstance.connect(owner).setRateLimit([DurationForUniswap, RateForUniswap])

                        const InitialSendFunds = ONE_ETH;

                        await mainInstance.connect(owner).claim(InitialSendFunds, charlie.address);
                        await mainInstance.connect(charlie).approve(uniswapRouterInstance.address, InitialSendFunds.div(2));
                        let ts = await time.latest();
                        let timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                        //swapExactTokensForTokensSupportingFeeOnTransferTokens
                        //swapExactTokensForTokens
                        await uniswapRouterInstance.connect(charlie).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                            InitialSendFunds.div(2), //uint amountIn,
                            0, //uint amountOutMin,
                            [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
                            charlie.address, //address to,
                            timeUntil //uint deadline   

                        );
                        // // try to send all that left
                        await mainInstance.connect(charlie).approve(uniswapRouterInstance.address, InitialSendFunds.div(2));

                        //PanicSellRateExceeded()
                        let charlieBalanceBeforePanic = await mainInstance.balanceOf(charlie.address);
                        let charlieBalanceReservedBeforePanic = await erc20ReservedToken.balanceOf(charlie.address);
                        let tx = await uniswapRouterInstance.connect(charlie).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                                InitialSendFunds.div(2), //uint amountIn,
                                0, //uint amountOutMin,
                                [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
                                charlie.address, //address to,
                                timeUntil //uint deadline   

                        );
                        let charlieBalanceAfterPanic = await mainInstance.balanceOf(charlie.address);
                        let charlieBalanceReservedAfterPanic = await erc20ReservedToken.balanceOf(charlie.address);
                        let rc = await tx.wait(); // 0ms, as tx is already confirmed
                        // let event = rc.events.find(event => event.event === 'PanicSellRateExceeded');
                        // console.log(rc.events);

                        // here fast and stupid way to find event PanicSellRateExceeded that cann't decoded if happens in external contract
                        let arr2compare = [
                            ethers.utils.id("PanicSellRateExceeded(address,address,uint256)"), // keccak256
                            '0x'+(charlie.address.replace('0x','')).padStart(64, '0'),
                            '0x'+(uniswapV2Pair.replace('0x','')).padStart(64, '0')
                        ]
                        let event = rc.events.find(event => JSON.stringify(JSON.stringify(event.topics)).toLowerCase() === JSON.stringify(JSON.stringify(arr2compare)).toLowerCase());
                        let eventExists = (typeof(event) !== 'undefined') ? true : false;
                        expect(eventExists).to.be.eq(true);
                        if (eventExists) {
                            // address: '0x2d13826359803522cCe7a4Cfa2c1b582303DD0B4',
                            // topics: [
                            //     '0xda8c6cfc61f9766da27a11e69038df366444016f44f525a2907f393407bfc6c3',
                            //     '0x00000000000000000000000090f79bf6eb2c4f870365e785982e1f101e93b906',
                            //     '0x0000000000000000000000009b7889734ac75060202410362212d365e9ee1ef5'
                            // ],
                            expect(event.address).to.be.eq(mainInstance.address);
                            expect(ethers.utils.getAddress( event.topics[1].replace('000000000000000000000000','') )).to.be.eq(charlie.address);
                            expect(ethers.utils.getAddress( event.topics[2].replace('000000000000000000000000','') )).to.be.eq(uniswapV2Pair);

                            // we will adjust value in panic situation from amount to 5
                            // so transaction didn't revert but emitted event "PanicSellRateExceeded"

                            expect(charlieBalanceBeforePanic.sub(5)).to.be.eq(charlieBalanceAfterPanic);
                            expect(charlieBalanceReservedBeforePanic.add(4)).to.be.eq(charlieBalanceReservedAfterPanic);
                        }
                        //----------------------
                    
                    }); 


                    it("shouldnt add liquidity", async() => {
                        let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                        [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                        maxliquidity = tradedReserve2.sub(tradedReserve1);
                        add2Liquidity = maxliquidity.abs()//.mul(1).div(10000);

                        await expect(mainInstance.connect(owner).addLiquidity(add2Liquidity)).to.be.revertedWith("PriceDropTooBig()");

                        // or try to max from maxAddLiquidity
                        // seems we can add ZERO. Contract will try to use max as possible
                        //await expect(mainInstance.connect(owner).addLiquidity(0)).to.be.revertedWith("CanNotBeZero()");

                        
 
                    });

                });
            
            });
             
        });

    });
    
});