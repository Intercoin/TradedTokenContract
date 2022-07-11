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

const FRACTION = BigNumber.from('100000');

chai.use(require('chai-bignumber')());

describe("itrV2", function () {
    const accounts = waffle.provider.getWallets();

    const owner = accounts[0];                     
    const alice = accounts[1];
    const bob = accounts[2];
    const charlie = accounts[3];
    const commissionReceiver = accounts[4];
    const liquidityHolder = accounts[5];

    const HOUR = 60*60; // * interval: DAY in seconds
    const dayInSeconds = 24*HOUR; // * interval: DAY in seconds
    const lockupIntervalCount = 365; // year in days(dayInSeconds)

    const tokenName = "Intercoin Investor Token";
    const tokenSymbol = "ITR";
    // const defaultOperators = [];
    // const initialSupply = TEN.mul(TEN.pow(SIX)).mul(TENIN18); // 10kk * 10^18
    // const maxTotalSupply = TEN.mul(TEN.pow(NINE)).mul(TENIN18); // 10kkk * 10^18
    const reserveToken = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; //” (USDC)
    const granularitySize = TWO;
    const priceDrop = FRACTION.mul(ONE).div(TEN);// 10% = 0.1   (and multiple fraction)
    const windowSize = ONE.mul(dayInSeconds);
// periodSize = windowSize_ / granularity_) * granularity_
//range [now - [windowSize, windowSize - periodSize * 2], now]
    
    const lockupIntervalAmount = 365;
    
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

    describe("validate params", function () {
        it("should correct granularitySize", async() => {
            await expect(
                MainFactory.connect(owner).deploy(
                    reserveToken, //” (USDC)
                    ZERO,
                    priceDrop,
                    windowSize,
                    lockupIntervalAmount
                )
            ).to.be.revertedWith("granularitySize invalid");
        });
        it("should correct window interval", async() => {
            await expect(
                MainFactory.connect(owner).deploy(
                    reserveToken, //” (USDC)
                    THREE,//granularitySize,
                    priceDrop,
                    HUN,//windowSize
                    lockupIntervalAmount
                )
            ).to.be.revertedWith("window not evenly divisible");
        });
        it("should correct reserveToken", async() => {
            await expect(
                MainFactory.connect(owner).deploy(
                    ZERO_ADDRESS, //” (USDC)
                    granularitySize,//granularitySize,
                    priceDrop,
                    windowSize,//windowSize
                    lockupIntervalAmount
                )
            ).to.be.revertedWith("reserveToken invalid");
        });
    });

    describe("instance check", function () {
        beforeEach("deploying", async() => {
            erc20ReservedToken = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
            mainInstance = await MainFactory.connect(owner).deploy(
                erc20ReservedToken.address, //” (USDC)
                granularitySize,
                priceDrop,
                windowSize,
                lockupIntervalAmount
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
    
        describe("uniswap settings", function () {
            var uniswapRouterFactoryInstance, uniswapRouterInstance, pairInstance;
            var snapId;

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

            beforeEach("adding liquidity", async() => {

                await erc20ReservedToken.connect(owner).mint(mainInstance.address, ONE_ETH.mul(TEN));
                await mainInstance.addInitialLiquidity(ONE_ETH.mul(TEN),ONE_ETH.mul(TEN));

                // uniswapRouterFactoryInstance = await ethers.getContractAt("IUniswapV2Factory",UNISWAP_ROUTER_FACTORY_ADDRESS);
                // uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);
            
                // let pairAddress = await uniswapRouterFactoryInstance.getPair(erc20ReservedToken.address, itrv2.address);

                // pairInstance = await ethers.getContractAt("ERC20Mintable",pairAddress);

                // await erc20ReservedToken.connect(owner).mint(owner.address, ONE_ETH.mul(TEN));
                // await mainInstance.connect(owner)["claim(uint256)"](ONE_ETH.mul(TEN));

                // await erc20ReservedToken.connect(owner).approve(uniswapRouterInstance.address, ONE_ETH.mul(TEN));
                // await itrv2.connect(owner).approve(uniswapRouterInstance.address, ONE_ETH.mul(TEN));

                // const ts = await time.latest();
                // const timeUntil = parseInt(ts)+parseInt(lockupIntervalCount*dayInSeconds);

                // await uniswapRouterInstance.connect(owner).addLiquidity(
                //     erc20ReservedToken.address,
                //     itrv2.address,
                //     ONE_ETH.mul(TEN),
                //     ONE_ETH.mul(TEN),
                //     0,
                //     0,
                //     owner.address,
                //     timeUntil
                // );
                await expect(
                    mainInstance.connect(owner).addLiquidity(ONE_ETH)
                ).to.be.revertedWith("MISSING_HISTORICAL_OBSERVATION");
                //console.log("111");
                await mainInstance.connect(owner).update();
                //console.log("222");
            });

            it("should update pair", async() => {

                // update by owner
                await mainInstance.connect(owner).update();
                // update by bob
                await mainInstance.connect(bob).update();
                
            }); 

            it("should add liquidity", async() => {

                let maxliquidity;
                for(let i = 0; i < 10; i++) {

                    await mainInstance.connect(owner).update();

                    await mainInstance.connect(owner).update();

                    await ethers.provider.send('evm_increaseTime', [parseInt(HOUR)]);
                    await ethers.provider.send('evm_mine');


                    maxliquidity = await mainInstance.maxAddLiquidity();

                    console.log("!MaxLiquidity = ", maxliquidity);

                    await mainInstance.connect(owner).addLiquidity(ONE.mul(maxliquidity).div(THOUSAND));

                }

                await printPrices("final");                                
            }); 

            describe("check update", function () {
                it("should be the same if price does not changes", async() => {

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

    
    


        // await erc20ReservedToken.mint(liquidityHolder.address, ONE_ETH.mul(TEN).mul(THOUSAND));
        // await erc20TradedToken.mint(liquidityHolder.address, ONE_ETH.mul(FOUR).mul(TEN).mul(THOUSAND));
        // await erc20ReservedToken.connect(liquidityHolder).approve(uniswapRouterInstance.address, ONE_ETH.mul(TEN).mul(THOUSAND));
        // await erc20TradedToken.connect(liquidityHolder).approve(uniswapRouterInstance.address, ONE_ETH.mul(FOUR).mul(TEN).mul(THOUSAND));

        // const ts = await time.latest();
        // const timeUntil = parseInt(ts)+parseInt(lockupIntervalCount*dayInSeconds);

        // await uniswapRouterInstance.connect(liquidityHolder).addLiquidity(
        //     erc20ReservedToken.address,
        //     erc20TradedToken.address,
        //     ONE_ETH.mul(TEN).mul(THOUSAND),             // 10000
        //     ONE_ETH.mul(FOUR).mul(TEN).mul(THOUSAND),   // 40000
        //     0,
        //     0,
        //     liquidityHolder.address,
        //     timeUntil
        // );

    
/*
    it("should correct token initialSupply", async() => {
        expect(await itrx.totalSupply()).to.be.equal(initialSupply);
    });

    it("should correct token maxTotalSupply", async() => {
        expect(await itrx.maxTotalSupply()).to.be.equal(maxTotalSupply);
    });

    it("should mint token person from whitelist only", async() => {
        const amountToMint = ONE.mul(TEN.pow(BigNumber.from('18')));
        let balanceBefore = await itrx.balanceOf(alice.address);
        await itrx.connect(owner).mint(alice.address, amountToMint);
        let balanceAfter = await itrx.balanceOf(alice.address);
        expect(balanceAfter.sub(balanceBefore)).to.be.eq(amountToMint);
    });

    it("no one should mint the token except persons from whitelist", async() => {
        const amountToMint = ONE.mul(TEN.pow(BigNumber.from('18')));
        await expect(
            itrx.connect(alice).mint(alice.address, amountToMint)
        ).to.be.revertedWith("must be in whitelist");
    });

    describe("uniswap tests", function () {
        var uniswapRouterFactoryInstance;
        var uniswapRouterInstance;
        var communityStakingPool;
        var pairInstance;

        const UNISWAP_ROUTER_FACTORY_ADDRESS = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
        const UNISWAP_ROUTER = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';
        const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'; // main
        
        beforeEach("deploying", async() => {
            uniswapRouterFactoryInstance = await ethers.getContractAt("IUniswapV2Factory",UNISWAP_ROUTER_FACTORY_ADDRESS);
            uniswapRouterInstance = await ethers.getContractAt("IUniswapRouter", UNISWAP_ROUTER);

            await uniswapRouterFactoryInstance.createPair(itrx.address, WETH);

            let pairAddress = await uniswapRouterFactoryInstance.getPair(itrx.address, WETH);
            pairInstance = await ethers.getContractAt("ERC20",pairAddress);

            await itrx.connect(owner).mint(owner.address, TEN.mul(TENIN18));
            await itrx.connect(owner).approve(uniswapRouterInstance.address, TEN.mul(TENIN18));

            const ts = await time.latest();
            const timeUntil = parseInt(ts)+parseInt('1000000000');

            await uniswapRouterInstance.connect(owner).addLiquidityETH(
                itrx.address,
                TEN.mul(TENIN18),
                0,
                0,
                owner.address,
                timeUntil
                ,{value: TEN.mul(TENIN18)}
            );
        });
        
        it("shouldnt exchange at uniswap", async() => {
            // here uniswap revert while transfer from pair to Bob but fall with own MSG "UniswapV2: TRANSFER_FAILED"
            await expect(
                 uniswapRouterInstance.connect(bob).swapExactETHForTokens(
                    0,                          //uint amountOutMin, 
                    [WETH,itrx.address],        //address[] calldata path, 
                    bob.address,                //address to, 
                    Math.floor(Date.now()/1000) //uint deadline
                    ,{value: ONE.mul(TENIN18)}
                )
            ).to.be.revertedWith("UniswapV2: TRANSFER_FAILED");

            const amountToTransfer = ONE.mul(TENIN18);
            await itrx.connect(owner).transfer(bob.address, amountToTransfer);
            await itrx.connect(bob).approve(uniswapRouterInstance.address, amountToTransfer);

            await expect(
                 uniswapRouterInstance.connect(bob).swapExactTokensForETH(
                    (ONE).mul(TENIN18).div(TEN),//amountToTransfer,           // uint amountIn, 
                    0,                          //uint amountOutMin, 
                    [itrx.address,WETH],        //address[] calldata path, 
                    bob.address,                //address to, 
                    Math.floor(Date.now()/1000) //uint deadline
                )
            ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
            // different message because uniswap try to 

        });

        it("should transfer [whitelist -> user] ", async() => {
            const balanceBefore = await itrx.balanceOf(bob.address);
            const amountToTransfer = ONE.mul(TENIN18);
            await itrx.connect(owner).transfer(bob.address, amountToTransfer);
            const balanceAfter = await itrx.balanceOf(bob.address);
            expect(balanceAfter.sub(balanceBefore)).to.be.eq(amountToTransfer);
        });

        it("shouldnt transfer user -> user ", async() => {
            const amountToTransfer = ONE.mul(TENIN18);
            await itrx.connect(owner).transfer(bob.address, amountToTransfer);

            await expect(
                itrx.connect(bob).transfer(alice.address, amountToTransfer)
            ).to.be.revertedWith("TRANSFER_DISABLED");
        });
        
        it("should transferFrom [whitelist -> user]", async() => {
            const amountToTransfer = ONE.mul(TENIN18);

            const balanceOwnerBefore = await itrx.balanceOf(owner.address);
            const balanceBobBefore = await itrx.balanceOf(bob.address);
            const balanceAliceBefore = await itrx.balanceOf(alice.address);

            await itrx.connect(owner).approve(bob.address, amountToTransfer);
            await itrx.connect(bob).transferFrom(owner.address, alice.address, amountToTransfer);

            const balanceOwnerAfter = await itrx.balanceOf(owner.address);
            const balanceBobAfter = await itrx.balanceOf(bob.address);
            const balanceAliceAfter = await itrx.balanceOf(alice.address);

            expect(balanceAliceAfter.sub(balanceAliceBefore)).to.be.eq(amountToTransfer);
            expect(balanceOwnerBefore.sub(balanceOwnerAfter)).to.be.eq(amountToTransfer);
            expect(balanceBobBefore).to.be.eq(balanceBobAfter);
        });

        it("shouldnt transferFrom user -> user ", async() => {
            const amountToTransfer = ONE.mul(TENIN18);
            await itrx.connect(owner).transfer(bob.address, amountToTransfer);

            await itrx.connect(bob).approve(alice.address, amountToTransfer);

            await expect(
                itrx.connect(alice).transferFrom(bob.address, charlie.address, amountToTransfer)
            ).to.be.revertedWith("TRANSFER_DISABLED");
        });

        it("should remove liquidity by person from whitelist", async() => {
            const lpTokensAmount = await pairInstance.balanceOf(owner.address);
            await pairInstance.connect(owner).approve(uniswapRouterInstance.address, lpTokensAmount);       
            await uniswapRouterInstance.connect(owner).removeLiquidity(
                itrx.address,                   // address tokenA,
                WETH,                           // address tokenB,
                lpTokensAmount.div(TWO),        // uint liquidity,
                0,                              // uint amountAMin,
                0,                              // uint amountBMin,
                owner.address,                  // address to,
                Math.floor(Date.now()/1000)+5000// uint deadline
            );

        });

        it("shouldnt remove liquidity by person outside whitelist", async() => {
            const lpTokensAmount = await pairInstance.balanceOf(owner.address);
            await pairInstance.connect(owner).transfer(bob.address, lpTokensAmount);
            await pairInstance.connect(bob).approve(uniswapRouterInstance.address, lpTokensAmount);       

            await expect(
                uniswapRouterInstance.connect(bob).removeLiquidity(
                    itrx.address,                   // address tokenA,
                    WETH,                           // address tokenB,
                    lpTokensAmount.div(TWO),        // uint liquidity,
                    0,                              // uint amountAMin,
                    0,                              // uint amountBMin,
                    bob.address,                    // address to,
                    Math.floor(Date.now()/1000)+5000// uint deadline
                )
            ).to.be.revertedWith("UniswapV2: TRANSFER_FAILED");


        });
    });
    */

});