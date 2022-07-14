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
const NINE = BigNumber.from('9');
const TEN = BigNumber.from('10');
const HUN = BigNumber.from('100');
const THOUSAND = BigNumber.from('1000');

const ONE_ETH = TEN.pow(BigNumber.from('18'));

const FRACTION = BigNumber.from('10000');

chai.use(require('chai-bignumber')());

describe("itrV2", function () {
    const accounts = waffle.provider.getWallets();

    const owner = accounts[0];                     
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];
    const commissionReceiver = accounts[4];
    const liquidityHolder = accounts[5];

    const HOUR = 60*60; // * interval: HOUR in seconds
    const DAY = 24*HOUR; // * interval: DAY in seconds

    const lockupIntervalAmount = 365; // year in days(dayInSeconds)

    const tokenName = "Intercoin Investor Token";
    const tokenSymbol = "ITR";
    // const defaultOperators = [];
    // const initialSupply = TEN.mul(TEN.pow(SIX)).mul(TENIN18); // 10kk * 10^18
    // const maxTotalSupply = TEN.mul(TEN.pow(NINE)).mul(TENIN18); // 10kkk * 10^18
    const reserveToken = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; //” (USDC)
    const priceDrop = FRACTION.mul(ONE).div(TEN);// 10% = 0.1   (and multiple fraction)
    const windowSize = DAY;
// periodSize = windowSize_ / granularity_) * granularity_
//range [now - [windowSize, windowSize - periodSize * 2], now]
    
    const minClaimPriceNumerator = 1;
    const minClaimPriceDenominator = 1000;

    const externalTokenExchangePriceNumerator = 1;
    const externalTokenExchangePriceDenominator = 1;

    // vars
    var mainInstance, itrv2, erc20ReservedToken;
    var MainFactory, ITRv2Factory, ERC20Factory;
    
    
    var printPrices = async function(str) {
        //return;
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
        MainFactory = await ethers.getContractFactory("MainMock");
        ITRv2Factory = await ethers.getContractFactory("ITRv2");
        ERC20Factory = await ethers.getContractFactory("ERC20Mintable");
    });

    it("shouldnt claim if externalToken params does not specify", async() => {
        var erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");

        mainInstance = await MainFactory.connect(owner).deploy(
            erc20ReservedToken.address, //” (USDC)
            priceDrop,
            windowSize,
            lockupIntervalAmount,
            [minClaimPriceNumerator, minClaimPriceDenominator],
            ZERO_ADDRESS, //externalToken.address,
            [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator]
        );

        await expect(
            mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address)
        ).to.be.revertedWith("externalToken is not set");
        
    });

    it("should external claim if exchange price 1:2", async() => {

        // make snapshot before time manipulations
        let snapId = await ethers.provider.send('evm_snapshot', []);
                    
        var erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
        var externalToken       = await ERC20Factory.deploy("ERC20 External Token", "ERC20-EXT");
        const customExternalTokenExchangePriceNumerator = 1;
        const customExternalTokenExchangePriceDenominator = 2;

        mainInstance = await MainFactory.connect(owner).deploy(
            erc20ReservedToken.address, //” (USDC)
            priceDrop,
            windowSize,
            lockupIntervalAmount,
            [minClaimPriceNumerator, minClaimPriceDenominator],
            externalToken.address,
            [customExternalTokenExchangePriceNumerator, customExternalTokenExchangePriceDenominator]
        );

        let erc777 = await mainInstance.tradedToken();
        itrv2 = await ethers.getContractAt("ITRv2",erc777);
        
        await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));
        await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));

        await mainInstance.connect(owner).update();

        await externalToken.connect(owner).mint(bob.address, ONE_ETH);
        let bobExternalTokenBalanceBefore = await externalToken.balanceOf(bob.address);
        let mainInstanceExternalTokenBalanceBefore = await externalToken.balanceOf(mainInstance.address);

        await externalToken.connect(bob).approve(mainInstance.address, ONE_ETH);

        await mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address);

        let bobExternalTokenBalanceAfter = await externalToken.balanceOf(bob.address);
        let mainInstanceExternalTokenBalanceAfter = await externalToken.balanceOf(mainInstance.address);

        expect(await itrv2.balanceOf(bob.address)).to.be.eq(ONE_ETH.mul(customExternalTokenExchangePriceNumerator).div(customExternalTokenExchangePriceDenominator));
        expect(bobExternalTokenBalanceBefore.sub(bobExternalTokenBalanceAfter)).to.be.eq(ONE_ETH);
        expect(mainInstanceExternalTokenBalanceAfter.sub(mainInstanceExternalTokenBalanceBefore)).to.be.eq(ZERO);

        // restore snapshot
        await ethers.provider.send('evm_revert', [snapId]);
    });


    describe("validate params", function () {
       
        it("should correct reserveToken", async() => {
            await expect(
                MainFactory.connect(owner).deploy(
                    ZERO_ADDRESS, //” (USDC)
                    priceDrop,
                    windowSize,//windowSize
                    lockupIntervalAmount,
                    [minClaimPriceNumerator, minClaimPriceDenominator],
                    ZERO_ADDRESS,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator]
                )
            ).to.be.revertedWith("reserveToken invalid");
        });
    });

    describe("instance check", function () {
        var externalToken;
        beforeEach("deploying", async() => {
            erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
            externalToken       = await ERC20Factory.deploy("ERC20 External Token", "ERC20-EXT");

            mainInstance = await MainFactory.connect(owner).deploy(
                erc20ReservedToken.address, //” (USDC)
                priceDrop,
                windowSize,
                lockupIntervalAmount,
                [minClaimPriceNumerator, minClaimPriceDenominator],
                externalToken.address,
                [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator]
            );

            let erc777 = await mainInstance.tradedToken();
            itrv2 = await ethers.getContractAt("ITRv2",erc777);

            
        });

        it("should correct token name", async() => {
            expect(await itrv2.name()).to.be.equal(tokenName);
        });

        it("should correct token symbol", async() => {
            expect(await itrv2.symbol()).to.be.equal(tokenSymbol);
        });

        it("shouldnt `update` without liquidity", async() => {
            await expect(
                mainInstance.connect(bob).update()
            ).to.be.revertedWith("RESERVES_EMPTY");
        }); 

        it("shouldnt `addLiquidity` without liquidity", async() => {
            await expect(
                mainInstance.connect(owner).addLiquidity(ONE_ETH)
            ).to.be.revertedWith("RESERVES_EMPTY");
        }); 

        describe("claim", function () {
            beforeEach("adding liquidity", async() => {

                await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));
                await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));

                await expect(
                    mainInstance.connect(owner).addLiquidity(ONE_ETH)
                ).to.be.revertedWith("MISSING_HISTORICAL_OBSERVATION");
                
                await mainInstance.connect(owner).update();
            });

            describe("internal", function () {
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

                it("should claim", async() => {
                    await expect(
                        mainInstance.connect(bob)["claim(uint256)"](ONE_ETH)
                    ).to.be.revertedWith("Ownable: caller is not the owner");

                    await expect(
                        mainInstance.connect(bob)["claim(uint256,address)"](ONE_ETH,bob.address)
                    ).to.be.revertedWith("Ownable: caller is not the owner");

                    await mainInstance.connect(owner)["claim(uint256)"](ONE_ETH);
                    expect(await itrv2.balanceOf(owner.address)).to.be.eq(ONE_ETH);
                });

                it("shouldnt `claim` if the price has become lower than minClaimPrice", async() => {
                    await expect(
                        mainInstance.connect(bob)["claim(uint256)"](ONE_ETH)
                    ).to.be.revertedWith("Ownable: caller is not the owner");

                    await expect(
                        mainInstance.connect(bob)["claim(uint256,address)"](ONE_ETH,bob.address)
                    ).to.be.revertedWith("Ownable: caller is not the owner");

                    await mainInstance.connect(owner)["claim(uint256)"](ONE_ETH);
                    expect(await itrv2.balanceOf(owner.address)).to.be.eq(ONE_ETH);
                });

                it("should locked up tokens after owner claim", async() => {
                    await mainInstance.connect(owner)["claim(uint256,address)"](ONE_ETH,bob.address);
                    expect(await itrv2.balanceOf(bob.address)).to.be.eq(ONE_ETH);

                    await expect(
                        itrv2.connect(bob).transfer(alice.address,ONE_ETH)
                    ).to.be.revertedWith("insufficient amount");
                }); 

                it("shouldnt locked up tokens if owner claim to himself", async() => {
                    await mainInstance.connect(owner)["claim(uint256)"](ONE_ETH);
                    expect(await itrv2.balanceOf(owner.address)).to.be.eq(ONE_ETH);

                    await itrv2.connect(owner).transfer(alice.address,ONE_ETH);
                    expect(await itrv2.balanceOf(alice.address)).to.be.eq(ONE_ETH);

                    await itrv2.connect(alice).transfer(bob.address,ONE_ETH);
                    expect(await itrv2.balanceOf(bob.address)).to.be.eq(ONE_ETH);
                    
                }); 
            }); 

            describe("external", function () {
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

                it("shouldnt claim via external token without approve before", async() => {
                    await expect(
                        mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address)
                    ).to.be.revertedWith("insufficient amount in allowance");
                });

                it("should claim via external token", async() => {

                    await externalToken.connect(owner).mint(bob.address, ONE_ETH);
                    let bobExternalTokenBalanceBefore = await externalToken.balanceOf(bob.address);
                    let mainInstanceExternalTokenBalanceBefore = await externalToken.balanceOf(mainInstance.address);

                    await externalToken.connect(bob).approve(mainInstance.address, ONE_ETH);

                    await mainInstance.connect(bob).claimViaExternal(ONE_ETH, bob.address);

                    let bobExternalTokenBalanceAfter = await externalToken.balanceOf(bob.address);
                    let mainInstanceExternalTokenBalanceAfter = await externalToken.balanceOf(mainInstance.address);

                    expect(await itrv2.balanceOf(bob.address)).to.be.eq(ONE_ETH);
                    expect(bobExternalTokenBalanceBefore.sub(bobExternalTokenBalanceAfter)).to.be.eq(ONE_ETH);
                    expect(mainInstanceExternalTokenBalanceAfter.sub(mainInstanceExternalTokenBalanceBefore)).to.be.eq(ZERO);
                });

            }); 
        });

        describe("uniswap settings", function () {
            var uniswapRouterFactoryInstance, uniswapRouterInstance, pairInstance;
            var snapId;

           

            beforeEach("adding liquidity", async() => {

                await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));
console.log("JS::adding liquidity:#1");
                await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));
console.log("JS::adding liquidity:#2");
//                 await expect(
//                     mainInstance.connect(owner).update()
//                 ).to.be.revertedWith("PERIOD_NOT_ELAPSED");
// console.log("JS::adding liquidity:#3");
//                 //console.log("111");
//                 ;
// console.log("JS::adding liquidity:#4");
//                 //console.log("222");
//                 await ethers.provider.send('evm_increaseTime', [parseInt(DAY)]);
//                 await ethers.provider.send('evm_mine');
// console.log("JS::adding liquidity:#5");
//                 await mainInstance.connect(owner).update();
//                 await expect(
//                     mainInstance.connect(owner).update()
//                 ).to.be.revertedWith("PERIOD_NOT_ELAPSED");
// console.log("JS::adding liquidity:#6");
                
                //uniswapRouterFactoryInstance = await ethers.getContractAt("IUniswapV2Factory",UNISWAP_ROUTER_FACTORY_ADDRESS);
                uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

///////////////////////////////////////////////
                let ts,timeUntil;
//                 await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.mul(TWO));
//                 await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.mul(TWO));
//                 ts = await time.latest();
//                 timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
//                 await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
//                     ONE_ETH.mul(TWO), //uint amountIn,
//                     0, //uint amountOutMin,
//                     [erc20ReservedToken.address, itrv2.address], //address[] calldata path,
//                     bob.address, //address to,
//                     timeUntil //uint deadline   
                
//                 );
//                 await ethers.provider.send('evm_increaseTime', [parseInt(DAY)]);
//                 await ethers.provider.send('evm_mine');

// await mainInstance.connect(owner).update();
                // await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.mul(TWO));
                // await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.mul(TWO));
                // ts = await time.latest();
                // timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
                // await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                //     ONE_ETH.mul(TWO), //uint amountIn,
                //     0, //uint amountOutMin,
                //     [erc20ReservedToken.address, itrv2.address], //address[] calldata path,
                //     bob.address, //address to,
                //     timeUntil //uint deadline   
                
                // );
// await ethers.provider.send('evm_increaseTime', [parseInt(DAY)]);
//                 await ethers.provider.send('evm_mine');
                
//                 await mainInstance.connect(owner).update();

await mainInstance.connect(owner).forceSync();
//for(let i =0; i<1; i++) {
    await ethers.provider.send('evm_increaseTime', [parseInt(DAY)]);
    await ethers.provider.send('evm_mine');
    await mainInstance.connect(owner).update(); 

    await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH.div(2));
    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH.div(2));
    ts = await time.latest();
    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
        ONE_ETH.div(2), //uint amountIn,
        0, //uint amountOutMin,
        [erc20ReservedToken.address, itrv2.address], //address[] calldata path,
        bob.address, //address to,
        timeUntil //uint deadline   
    
    );
    
  
//}



            });
            
            describe("checks", function () {
                var snapId;
                beforeEach("make snapshot", async() => {
console.log("make snapshot");
let x1,x2,x3;
[x1,x2,x3] = await mainInstance.uniswapPricesSimple();
console.log("x1 =",x1);
console.log("x2 =",x2);
                    // make snapshot before time manipulations
                    snapId = await ethers.provider.send('evm_snapshot', []);
                    console.log("make snapshot `"+snapId+"`");
                });

                afterEach("revert to snapshot", async() => {
                    // restore snapshot
                    await ethers.provider.send('evm_revert', [snapId]);
                    console.log("revert to snapshot `"+snapId+"`");
                });

                it("should update pair", async() => {

                    // update by owner
                    await mainInstance.connect(owner).update();
                    // update by bob
                    await mainInstance.connect(bob).update();
                    
                }); 

                it("should add liquidity(10 times). maxAddLiquidity grow down. ", async() => {
// console.log("erc20ReservedToken.address = ", erc20ReservedToken.address);
// console.log("itrv2.address              = ", itrv2.address);
                    let maxliquidity;
                    let maxliquidities = [];
                    for(let i = 0; i < 10; i++) {

                        await mainInstance.connect(owner).update();

                        await mainInstance.connect(owner).update();

                        await ethers.provider.send('evm_increaseTime', [parseInt(HOUR)]);
                        await ethers.provider.send('evm_mine');


                        maxliquidity = await mainInstance.maxAddLiquidity();
                        maxliquidities.push(maxliquidity);
                        //console.log("!MaxLiquidity = ", maxliquidity);
                        // try to add (maxliquidity - maxliquidity/1000) to avoid js accuracy
                        await mainInstance.connect(owner).addLiquidity(maxliquidity.sub(maxliquidity.div(THOUSAND)));
// console.log("==============");
// [x1,x2,x3] = await mainInstance.uniswapPricesSimple();
// console.log("x1 =",x1);
// console.log("x2 =",x2);

                    }


//console.log(maxliquidities);
                    for (let i = 1; i < maxliquidities.length; i++) {
                        expect(maxliquidities[i-1]).to.be.gt(maxliquidities[i]);
                    }

                    //await printPrices("final");                                
                }); 

                it.only("maxAddLiquidity should grow up, when users swaping Reserve token to Traded token. (traded reserve decreasing)", async() => {

                    let maxliquidity,tradedReserve1,tradedReserve2;
                    let maxliquidities = [];
                    let tmp = [];
                    for(let i = 0; i < 8; i++) {
console.log("==============");
[x1,x2,x3] = await mainInstance.uniswapPricesSimple();
console.log("x1 =",x1);
console.log("x2 =",x2);
let pairObservation = await  mainInstance.pairObservation();
console.log("price0Average=", pairObservation.price0Average._x);
console.log("price1Average=", pairObservation.price1Average._x);
console.log("up№1");
                        // await expect(
                        //     mainInstance.connect(owner).update()
                        // ).to.be.revertedWith("PERIOD_NOT_ELAPSED");
console.log("up№2");
                        
console.log("up№3");
//await mainInstance.connect(owner).forceSync();
                        await ethers.provider.send('evm_increaseTime', [parseInt(DAY)]);
                        await ethers.provider.send('evm_mine');
                        await mainInstance.connect(owner).update();
                        // await expect(
                        //     mainInstance.connect(owner).update()
                        // ).to.be.revertedWith("PERIOD_NOT_ELAPSED");

console.log("maxAddL№1");
                        [tradedReserve1,tradedReserve2] = await mainInstance.connect(owner).maxAddLiquidity();
console.log("maxAddL№2");
tmp.push([tradedReserve1,tradedReserve2]);
                        maxliquidity = tradedReserve1.sub(tradedReserve2);
                        maxliquidities.push(maxliquidity);

                        await erc20ReservedToken.connect(owner).mint(bob.address, ONE_ETH);

                        await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, ONE_ETH);


                        const ts = await time.latest();
                        const timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
console.log("№1");
                        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                            ONE_ETH, //uint amountIn,
                            0, //uint amountOutMin,
                            [erc20ReservedToken.address, itrv2.address], //address[] calldata path,
                            bob.address, //address to,
                            timeUntil //uint deadline   
                            
                        );
console.log("№2");                        

// console.log(tmp);
// console.log(maxliquidities);
// return;
                    }
console.log(tmp);
console.log(maxliquidities);

                    for (let i = 1; i < maxliquidities.length; i++) {
                        expect(maxliquidities[i-1]).to.be.lt(maxliquidities[i]);
                    }

                }); 

                it("price should be the same when call update only", async() => {

                    let x1,x2,x3,x4,x5,x6,x7;
                    let priceTraded,averagePriceTraded;
                    
                    let prices = [];

                    for(var i = 0; i < 5; i++){
                        
                        await mainInstance.connect(owner).update();
                        await mainInstance.connect(owner).update();
                        await ethers.provider.send('evm_increaseTime', [parseInt(HOUR)]);
                        await ethers.provider.send('evm_mine');

                        [x1,x2,priceTraded,x4,averagePriceTraded,x6,x7] = await mainInstance.uniswapPrices();
                        prices.push([priceTraded,averagePriceTraded]);
                    }

                    
                    
                    [x1,x2,priceTraded,x4,averagePriceTraded,x6,x7] = await mainInstance.uniswapPrices();
                    prices.push([priceTraded,averagePriceTraded]);

                    for (let i = 1; i < prices.length; i++) {
                        expect(prices[i][0]).to.be.eq(prices[i][1]);
                        expect(prices[i-1][0]).to.be.eq(prices[i][0]);
                    }
                    

                });
            });
             
        });
    });
});