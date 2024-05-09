const { ethers, waffle } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('chai');
const chai = require('chai');
const { time } = require('@openzeppelin/test-helpers');
const fs = require('fs');
const XMLHttpRequest = require("xmlhttprequest").XMLHttpRequest;

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

function get_data(fname) {
    return new Promise(function(resolve, reject) {
        fs.readFile('./fname', (err, data) => {
            if (err) {
				
                if (err.code == 'ENOENT' && err.syscall == 'open' && err.errno == -4058) {
                    fs.writeFile('./'+fname, "", (err2) => {
                        if (err2) throw err2;
                        resolve();
                    });
                    data = ""
                } else {
                    throw err;
                }
            }
    
            resolve(data);
        });
    });
}

function write_data(fname, _message) {
    return new Promise(function(resolve, reject) {
        fs.writeFile('./'+fname, _message, (err) => {
            if (err) throw err;
            console.log('Data written to file');
            resolve();
        });
    });
}

async function delay(time) {
    return new Promise(resolve => setTimeout(resolve, time));
}

describe("Montecarlo tests", function () {
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
    const pricePercentsDrop = 20;// 10% = 0.1   (and multiple fraction)
    const priceDrop = FRACTION.mul(pricePercentsDrop).div(HUN);// 10% = 0.1   (and multiple fraction)
    
    const minClaimPriceNumerator = BigNumber.from('1');
    const minClaimPriceDenominator = BigNumber.from('10000');

    const minClaimPriceGrowNumerator = BigNumber.from('1');
    const minClaimPriceGrowDenominator = BigNumber.from('10000');

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
        0,//false,
        0,//false
    ];

    // vars
    var mainInstance, erc20ReservedToken;
    var MainFactory, ERC20Factory;
    var uniswapRouterInstance;
    
    function randomIntFromInterval(min, max) { // min and max included 
        return Math.floor(Math.random() * (max - min + 1) + min)
    }
    
    var printPrices = async function(str) {
        // return;
        // console.log(mainInstance.address);
        // let x1,x2,x3,x4,x5;
        // [x1,x2,x3,x4,x5] = await mainInstance.uniswapPrices();
        // console.log("======"+str+"============================");
        // console.log("reserveTraded  = ",x1.toString());
        // console.log("reserveReserved= ",x2.toString());
        // console.log("priceTraded    = ",x3.toString());
        // console.log("priceReserved  = ",x4.toString());
        // console.log("blockTimestamp = ",x5.toString());

        var tradedReserve1, tradedReserve2, priceAv;
        [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();
        console.log("======"+str+"============================");
        console.log("tradedReserve1 = ",tradedReserve1.toString());
        console.log("tradedReserve2 = ",tradedReserve2.toString());
        console.log("priceAv        = ",priceAv.toString());
        console.log("======"+str+"END==========================");
        
    }              
    //any_name_2023-11-29T17:46:30.408Z.json'
    var filename;
    var fileDataTmp;

    beforeEach("deploying", async() => {
        fileDataTmp = {};
        console.log("this.ctx.currentTest.title");
        console.log(this.ctx.currentTest.title);
        filename = `${this.ctx.currentTest.title}_${(new Date().toJSON())}`;
        filename = filename.replace(/[&\/\\#,+()$~%.'":*?<>{}]/g,'_');

        fileDataTmp['title'] = filename;
        filename += '.json';
        fileDataTmp['data'] = {};

        
        


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

        

        erc20ReservedToken  = await ERC20Factory.deploy("ERC20 Reserved Token", "ERC20-RSRV");
        //externalToken       = await ERC20Factory.deploy("ERC20 External Token", "ERC20-EXT");

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
        

        //200_000_000 tradedtokens
        //4_000_000 USDC tokens
        // var mint4AddingLiquidityUSDC = FOURTH.mul(THOUSAND).mul(THOUSAND).mul(ONE_ETH);
        // var mint4AddingLiquidityTradedToken = TWO.mul(HUN).mul(THOUSAND).mul(THOUSAND).mul(ONE_ETH);

        // 10_000_000 Traded tokens
        // 10_000 USDC
        var mint4AddingLiquidityUSDC = TEN.mul(THOUSAND).mul(ONE_ETH);
        var mint4AddingLiquidityTradedToken = TEN.mul(THOUSAND).mul(THOUSAND).mul(ONE_ETH);
        await erc20ReservedToken.connect(owner).mint(mainInstance.address, mint4AddingLiquidityUSDC);


        //await mainInstance.addInitialLiquidity(mint4AddingLiquidityTradedToken,mint4AddingLiquidityUSDC);
        await mainInstance.addInitialLiquidity(mint4AddingLiquidityTradedToken,mint4AddingLiquidityUSDC);
        
        uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", UNISWAP_ROUTER);

        //printPrices();
        
        const smthFromOwner = 1;
        await mainInstance.connect(owner).enableClaims();
        await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
    });
    afterEach("aftereach", async() => {
        await write_data('./montecarlo/data/' + filename, JSON.stringify(fileDataTmp, null, 2));
    });

    // it("FOOBAR1", async() => {
    //     [...Array(20)].forEach((_, i) => {fileDataTmp["data"].push(Math.floor(Math.random() * (20 - 1 + 1) + 1))});
    // }); 
    
    it("test buy liquidity as max as possible", async() => {
        fileDataTmp['data']['series'] = [];
        var series1 = {
            name: 'TotalSupply',
            type: 'spline',
            yAxis: 1,
            tooltip: {
                valueSuffix: ' tokens'
            },
            data: []
        };
        var series2 = {
            name: 'UniswapPrice',
            type: 'spline',
            yAxis: 2,
            tooltip: {
                valueSuffix: ' $'
            },
            data: []
        };

        //const Http = new XMLHttpRequest();
        var startPrice;
        var totalAddedAdditionalLiquidity = BigNumber.from(0);
        //var url;

        // make first swap overwise maxAddLiquidity will crash div divide zero;!!!
        amountToSwap = ONE_ETH;
        await erc20ReservedToken.connect(owner).mint(bob.address, amountToSwap);
        await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, amountToSwap);
        var ts = await time.latest();
        var timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
            amountToSwap, //uint amountIn,
            0, //uint amountOutMin,
            [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
            bob.address, //address to,
            timeUntil //uint deadline   

        );


        // 

        [tradedReserve1, tradedReserve2, ,,,,,priceAv] = await mainInstance.connect(owner).totalInfo();
        var paramAmount = 0;
        var paramTitle = "init";
        var paramPrice = tradedReserve2/tradedReserve1;

        //
        //fileDataTmp['data'].push(paramPrice.toString());
        var totalSupply = await mainInstance.connect(owner).totalSupply();
        series1['data'].push((totalSupply/1e18).toFixed(2));
        series2['data'].push(paramPrice.toFixed(4));
        // url='http://localhost:8080/add?amount='+paramAmount.toString()+'&title='+paramTitle.toString()+'&price='+paramPrice.toString();
        // Http.open("GET", url);
        // await Http.send();
        // await delay(100);

        //--------------------
        var maxIterationsCount = 1000;
        var i = 0;
        while (i<maxIterationsCount) {

            if (i % 20 == 0 && i != 0) {

                console.log("trying to add liquidity");
                let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();
                maxliquidity = tradedReserve2.sub(tradedReserve1);

                let tryAgain = true;
                while(tryAgain) {
                    try {
                        if (maxliquidity>1_000_000_000) {
                            await mainInstance.connect(owner).addLiquidity(maxliquidity);
                        }
                        tryAgain = false;
                        
                        [tradedReserve1, tradedReserve2, ,,,,,priceAv] = await mainInstance.connect(owner).totalInfo();
                        
                        var paramPrice = tradedReserve2/tradedReserve1;
                        // console.log(priceAv);
                        // var paramPrice = priceAv;
                        

                        //const url='http://localhost:8080/add?amount_reserve2='+tradedReserve2.toString()+'&amount_reserve1='+tradedReserve1.toString()+'&amount_buy=0&amount_sell=0&title=Liquidity&price='+paramPrice.toString();
                        //
                        //fileDataTmp['data'].push(paramPrice.toFixed(2));
                        var totalSupply = await mainInstance.connect(owner).totalSupply();
                        series1['data'].push((totalSupply/1e18).toFixed(2));
                        series2['data'].push(paramPrice.toFixed(4));
                        
                        // Http.open("GET", url);
                        // Http.send();
                        // await delay(100);

                        await ethers.provider.send('evm_increaseTime', [3600]); // pass 1 hour
                        await ethers.provider.send('evm_mine');
                        console.log("maxliquidity[success] = "+maxliquidity.toString());
                    
                    } catch(e) {
                        maxliquidity = maxliquidity.abs().mul(6).div(100);

                        
                    }
                    
                }
                if (tryAgain == true) {
                    console.log("maxliquidity[error] = seem price too big");
                }
                if (maxliquidity<1_000_000_000) {
                    console.log("(maxliquidity<1_000_000_000)");
                }
            }
            
            try {        
                
                // swap traded token to tradedToken
                //amountToSwap = (BigNumber.from(randomIntFromInterval(10_000,10_000))).mul(ONE_ETH);
                amountToSwap = (BigNumber.from(1_000)).mul(ONE_ETH);
                //amountToSwap = (BigNumber.from((i)*10)).mul(ONE_ETH);
                console.log("amountToSwap = ", amountToSwap.toString());

                await erc20ReservedToken.connect(owner).mint(bob.address, amountToSwap);
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, amountToSwap);
                ts = await time.latest();
                timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                let tx= await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    amountToSwap, //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                
            } catch(e) {
                console.log(e.toString());
                
            }

           
            //4------send to sat

            [tradedReserve1, tradedReserve2, ,,,,,priceAv] = await mainInstance.connect(owner).totalInfo();

            var paramPrice = tradedReserve2/tradedReserve1;
            //--
            //fileDataTmp['data'].push(paramPrice.toString());
            var totalSupply = await mainInstance.connect(owner).totalSupply();
            series1['data'].push((totalSupply/1e18).toFixed(2));
            series2['data'].push(paramPrice.toFixed(4));
            // url='http://localhost:8080/add?amount='+paramAmount.toString()+'&title='+paramTitle.toString()+'&price='+paramPrice.toString();
            // Http.open("GET", url);
            // await Http.send();
            // await delay(100);
            console.log(paramPrice.toFixed(4));

            await ethers.provider.send('evm_increaseTime', [3600]); // pass 1 hour
            await ethers.provider.send('evm_mine');
            //---------
            i++;
            
            if (i % 50 == 0 && i != 0) {
                console.log("Iteration:# "+i);
            }
        } // until

        fileDataTmp['data']['series'].push(series1);
        fileDataTmp['data']['series'].push(series2);


    });

    it.only("test random buy/sell", async() => {
        fileDataTmp['data']['series'] = [];
        var series1 = {
            name: 'TotalSupply',
            type: 'spline',
            yAxis: 1,
            tooltip: {
                valueSuffix: ' tokens'
            },
            data: []
        };
        var series2 = {
            name: 'UniswapPrice',
            type: 'spline',
            yAxis: 2,
            tooltip: {
                valueSuffix: ' $'
            },
            data: []
        };
        
        const Http = new XMLHttpRequest();
        var startPrice;
        var totalAddedAdditionalLiquidity = BigNumber.from(0);

        var amountToSwap; 
        var buysell;

        var maxIterationsCount = 1000;
        var i = 0;
        
        var countb=0;
        var counts=0;
        var tradedReserve1, tradedReserve2, priceAv, price0Cumulative,price1Cumulative,timestampLast,price0CumulativeLast,blockTimestamp,tmp;
        var balance;

        
        var liqAmount = 0;

        // make first swap overwise maxAddLiquidity will crash div divide zero;!!!
        amountToSwap = ONE_ETH;
        await erc20ReservedToken.connect(owner).mint(bob.address, amountToSwap);
        await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, amountToSwap);
        var ts = await time.latest();
        var timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
            amountToSwap, //uint amountIn,
            0, //uint amountOutMin,
            [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
            bob.address, //address to,
            timeUntil //uint deadline   

        );

        [tradedReserve1, tradedReserve2,,,,,,] = await mainInstance.connect(owner).totalInfo();
        startPrice = tradedReserve2/tradedReserve1;

        while (i<maxIterationsCount) {
            if (i % 30 == 0 && i != 0) {

                console.log("Iteration:# "+i);
                let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();
                maxliquidity = tradedReserve2.sub(tradedReserve1);

                let tryAgain = true;
                while(tryAgain) {
                    try {
                        if (maxliquidity>1_000_000_000) {
                            await mainInstance.connect(owner).addLiquidity(maxliquidity);
                        }
                        tryAgain = false;
                        console.log("maxliquidity=",maxliquidity.toString());
                        totalAddedAdditionalLiquidity = totalAddedAdditionalLiquidity.add(BigNumber.from(maxliquidity));

                        [tradedReserve1, tradedReserve2, ,,,,,priceAv] = await mainInstance.connect(owner).totalInfo();
                        
                        var paramPrice = tradedReserve2/tradedReserve1;
                        // console.log(priceAv);
                        // var paramPrice = priceAv;
                        

                        const url='http://localhost:8080/add?amount_reserve2='+tradedReserve2.toString()+'&amount_reserve1='+tradedReserve1.toString()+'&amount_buy=0&amount_sell=0&title=Liquidity&price='+paramPrice.toString();
                        //
                        //fileDataTmp['data'].push(paramPrice.toFixed(2));
                        var totalSupply = await mainInstance.connect(owner).totalSupply();
                        series1['data'].push((totalSupply/1e18).toFixed(2));
                        series2['data'].push(paramPrice.toFixed(4));
                        
                        // Http.open("GET", url);
                        // Http.send();
                        // await delay(100);

                        await ethers.provider.send('evm_increaseTime', [3600]); // pass 1 hour
                        await ethers.provider.send('evm_mine');

                    } catch(e) {
                        maxliquidity = maxliquidity.abs().mul(6).div(100);

                        console.log("maxliquidity[error]"+e.toString());
                    }
                }

                if (maxliquidity<1_000_000_000) {
                    console.log("(maxliquidity<1_000_000_000)");
                }
            }

            console.log("Iteration:# "+i);
            try {        
                
                if (i < maxIterationsCount/2) {
                    buysell = randomIntFromInterval(-500,1000) > 0 ? true : false;
                } else {
                    buysell = randomIntFromInterval(-1000,500) > 0 ? true : false;
                }


                if (buysell) {

                    // swap traded token to tradedToken
                    amountToSwap = (BigNumber.from(randomIntFromInterval(10_000,10_000))).mul(ONE_ETH);

                    await erc20ReservedToken.connect(owner).mint(bob.address, amountToSwap);
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.address, amountToSwap);
                    ts = await time.latest();
                    timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);

                    let tx= await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        amountToSwap, //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.address, mainInstance.address], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );

                    // let eventName = ethers.utils.keccak256(ethers.utils.toUtf8Bytes("Swap(address indexed sender,uint amount0In,uint amount1In,uint amount0Out,uint amount1Out,address indexed to)"))
                    // let rc= await tx.wait();
                    // console.log(rc.logs);
                    // console.log(rc.events);
                    // console.log(eventName);
                    // return;
                    // console.log('!!!!===================!!!!');
                    // var factoryAddr = await uniswapRouterInstance.factory();
                    // //console.log(factoryAddr);
                    // var factory = await ethers.getContractAt("IUniswapV2Factory", factoryAddr);
                    // var pairAddr = await factory.getPair(erc20ReservedToken.address, mainInstance.address);

                    // //console.log(pairAddr);
                    // var pair = await ethers.getContractAt("IUniswapV2Pair", pairAddr);
                    // console.log("token0 = ", await pair.token0());
                    // console.log("main   = ", mainInstance.address);
                    // return;
                    // // let tx2 = await pair.sync();
                    // // let rc2 = await tx2.wait();
                    // // console.log(rc2.logs);
                    // // console.log(rc2.events);
                    // //console.log("pair.timestampLast = ",await pair.timestampLast());

                    // console.log('!!!!sync!!!!');

                    

                    countb+=1;
                } else {

                    amountToSwap = randomIntFromInterval(10_000,10_000);
                    amountToSwap = (BigNumber.from(amountToSwap.toString())).mul(ONE_ETH);

                    balance = await mainInstance.balanceOf(bob.address);

                    if (balance > 0) {

                        if (parseFloat(balance) < parseFloat(amountToSwap)) {
                            amountToSwap = randomIntFromInterval(0,balance);
                            amountToSwap = amountToSwap.toLocaleString('fullwide', {useGrouping:false});
                        }

                        await mainInstance.connect(bob).approve(uniswapRouterInstance.address, amountToSwap);

                        ts = await time.latest();
                        timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
                        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                            amountToSwap, //uint amountIn,
                            0, //uint amountOutMin,
                            [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
                            bob.address, //address to,
                            timeUntil //uint deadline   

                        );

                        counts+=1;
                    } else {
                        
                        throw new Error('enough balance');
                    }
                    
                }

                //await printPrices();

                // (
                //     uint112 r0, uint112 r1, uint32 blockTimestamp,
                //     uint price0Cumulative, uint price1Cumulative,
                //     uint64 timestampLast, uint price0CumulativeLast, uint224 price0Average
                // )
                
                [tradedReserve1, tradedReserve2,blockTimestamp,price0Cumulative,price1Cumulative,timestampLast,price0CumulativeLast,priceAv] = await mainInstance.connect(owner).totalInfo();
                
                // console.log("tradedReserve1     =",(tradedReserve1).toString());
                // console.log("tradedReserve2     =",(tradedReserve2).toString());
                // console.log("blockTimestamp     =",(blockTimestamp).toString());
                // console.log("price0Cumulative   =",(price0Cumulative).toString());
                // console.log("price1Cumulative   =",(price1Cumulative).toString());
                // console.log("timestampLast      =",(timestampLast).toString());
                // console.log("price0CumulativLast=",(price0CumulativeLast).toString());
                // console.log("priceAv            =",(priceAv).toString());
                // console.log("==================================================================");
                
                
                //prices.push((tradedReserve2/tradedReserve1).toString());
                //amounts.push(buysell ? amountToSwap.toString() : (-amountToSwap).toString());
                //titles.push(i);
                
                //
                
                var paramAmountSell = buysell ? amountToSwap : 0;
                var paramAmountBuy = buysell ? 0 : (-amountToSwap);
                paramAmountSell = (paramAmountSell/1_000_000_000_000_000).toFixed()/(1_000);
                paramAmountBuy = (paramAmountBuy/1_000_000_000_000_000).toFixed()/(1_000);
                var paramTitle = i;
                var paramPrice = tradedReserve2/tradedReserve1;
                // console.log(priceAv);
                // var paramPrice = priceAv;
                //
                //fileDataTmp['data'].push(paramPrice.toFixed(2));
                var totalSupply = await mainInstance.connect(owner).totalSupply();
                series1['data'].push((totalSupply/1e18).toFixed(2));
                series2['data'].push(paramPrice.toFixed(4));
                // const url='http://localhost:8080/add?amount_reserve2='+tradedReserve2.toString()+'&amount_reserve1='+tradedReserve1.toString()+'&amount_buy='+paramAmountBuy.toString()+'&amount_sell='+paramAmountSell.toString()+'&title='+paramTitle.toString()+'&price='+paramPrice.toString();

                // Http.open("GET", url);
                // Http.send();
                // await delay(100);
                await ethers.provider.send('evm_increaseTime', [3600]); // pass 1 hour
                await ethers.provider.send('evm_mine');

                i++;
                
            } catch(e) {
    
                console.log(e.toString());
            }
        } //while

        
        // full sell
        balance = await mainInstance.balanceOf(bob.address);
        await mainInstance.connect(bob).approve(uniswapRouterInstance.address, balance);

        ts = await time.latest();
        timeUntil = parseInt(ts)+parseInt(lockupIntervalAmount*DAY);
        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
            balance, //uint amountIn,
            0, //uint amountOutMin,
            [mainInstance.address, erc20ReservedToken.address], //address[] calldata path,
            bob.address, //address to,
            timeUntil //uint deadline   

        );

        [tradedReserve1, tradedReserve2, ,,,,,priceAv] = await mainInstance.connect(owner).totalInfo();

        var paramAmountSell = 0;
        var paramAmountBuy = (-balance);
        paramAmountSell = (paramAmountSell/1_000_000_000_000_000).toFixed()/(1_000);
        paramAmountBuy = (paramAmountBuy/1_000_000_000_000_000).toFixed()/(1_000);
        var paramTitle = i;
        var paramPrice = tradedReserve2/tradedReserve1;
        // console.log(priceAv);
        // var paramPrice = priceAv;
        //
        //fileDataTmp['data'].push(paramPrice.toFixed(2));
        var totalSupply = await mainInstance.connect(owner).totalSupply();
        series1['data'].push((totalSupply/1e18).toFixed(2));
        series2['data'].push(paramPrice.toFixed(4));
        // const url='http://localhost:8080/add?amount_reserve2='+tradedReserve2.toString()+'&amount_reserve1='+tradedReserve1.toString()+'&amount_buy='+paramAmountBuy.toString()+'&amount_sell='+paramAmountSell.toString()+'&title='+paramTitle.toString()+'&price='+paramPrice.toString();
        // Http.open("GET", url);
        // Http.send();
        // await delay(100);
        await ethers.provider.send('evm_increaseTime', [3600]); // pass 1 hour
        await ethers.provider.send('evm_mine');
        

        fileDataTmp['data']['series'].push(series1);
        fileDataTmp['data']['series'].push(series2);
        console.log(fileDataTmp);
        // console.log(fileDataTmp['data']);
        // console.log(fileDataTmp['data']['series']);
        // var data_object = {
        //     "prices": prices,
        //     "amounts": amounts,
        //     "titles": titles
        // };
        console.log("StartPrice = ", startPrice.toString());
        console.log("FinalPrice = ", paramPrice.toString());

        console.log("AdditionalLiq = ", (totalAddedAdditionalLiquidity.toString()));
        
        console.log("Did Buys "+ countb+'/'+maxIterationsCount);
        console.log("Did Sells "+ counts+'/'+maxIterationsCount);
        
        //let data_to_write = JSON.stringify(data_object, null, 2);
        
        //await write_data(filename, data_to_write);

    });
})