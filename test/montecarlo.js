const { expect } = require('chai');
const hre = require("hardhat");
require("@nomicfoundation/hardhat-chai-matchers");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { constants} = require("@openzeppelin/test-helpers");

const { 
    deploy, 
    deploy2, 
    deploy3, 
    deploy4, 
    deploy5,
    deployInPresale,
    deployAndTestUniswapSettings,
    deployAndTestUniswapSettingsWithFirstSwap,
    deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted
} = require("./fixtures/deploy.js");
const { increase } = require('@openzeppelin/test-helpers/src/time.js');

const DEAD_ADDRESS = '0x000000000000000000000000000000000000dEaD';
const FRACTION = BigInt('10000');

async function addNewHolderAndSwap(data) {
    // here manipulations which need to do before each claim:
    //  buy - to get some tokens
    //  swap - to setup twap price
    //------------------
    const reserveTokenToSwap = ethers.parseEther("0.5");
    await data.erc20ReservedToken.connect(data.owner).mint(data.account.address, reserveTokenToSwap);
    await data.erc20ReservedToken.connect(data.account).approve(data.uniswapRouterInstance.target, reserveTokenToSwap);

    var ts = await time.latest();
    var timeUntil = BigInt(ts) + data.lockupIntervalAmount*24n*60n*60n;
    // buy 
    const expectedTokens = ethers.parseEther("1");
    const calculatedBuySellTokensAmount = expectedTokens * FRACTION / data.buyPrice;
    await data.buySellToken.connect(data.owner).mint(data.account.address, calculatedBuySellTokensAmount);
    await data.buySellToken.connect(data.account).approve(data.mainInstance.target, calculatedBuySellTokensAmount);
    await data.mainInstance.connect(data.account).buy(expectedTokens);
    //swap
    await data.uniswapRouterInstance.connect(data.account).swapExactTokensForTokens(
        reserveTokenToSwap, //uint amountIn,
        0, //uint amountOutMin,
        [data.erc20ReservedToken.target, data.mainInstance.target], //address[] calldata path,
        data.account.address, //address to,
        timeUntil //uint deadline   
    );
}

describe("montecarlo tests", function () {
    xit("maximum claim tokens", async() => {
        const {
            owner,
            bob,
            charlie,
            buyPrice,
            lockupIntervalAmount,
            emissionFrequency,
            erc20ReservedToken,
            buySellToken,
            uniswapRouterInstance,
            mainInstance
        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);
        var totalClaimed = 0n;
        var availableToClaimAreZERO = false;
        
        var wasAddedLquidity = false;
        var breakLoop = false;
        var iterations = 0n;

        while (!breakLoop) {
            
            var availableToClaim = await mainInstance.availableToClaim();
            console.log("availableToClaim       = ", availableToClaim);
            // console.log("availableToClaimAreZERO= ", availableToClaimAreZERO);
            // console.log("wasAddedLquidity       = ", wasAddedLquidity);
            // console.log("breakLoop              = ", breakLoop);
            // console.log("=================================");
            if (iterations > 300) {
                breakLoop = true;
                continue;
            }
            if (wasAddedLquidity) {
                if (availableToClaim == 0n) {
                    breakLoop = true;
                    continue;
                } else {
                    wasAddedLquidity = false;
                    availableToClaimAreZERO = false;
                }
            }

            
            if (availableToClaimAreZERO) {
                if (availableToClaim == 0n) {
                    console.log("mainInstance.connect(owner).addLiquidity(add2Liquidity);");
                    wasAddedLquidity = true;
                    //////////////////////////
                    let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                    [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();
                    maxliquidity = tradedReserve2 - tradedReserve1;
                    add2Liquidity = maxliquidity / 1000n;
                    await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                    //--
                    await time.increase(emissionFrequency);
                    ////////////////////////
                    continue;
                } else {
                    availableToClaimAreZERO = false;
                }
            }

            if (availableToClaim == 0n) {
                availableToClaimAreZERO = true;
                await time.increase(emissionFrequency);
                console.log("await time.increase(emissionFrequency)");
                continue;
            }
            

            
            // console.log("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
            // console.log("availableToClaim       = ", availableToClaim);
            // console.log("availableToClaimAreZERO= ", availableToClaimAreZERO);
            // console.log("wasAddedLquidity       = ", wasAddedLquidity);
            // console.log("breakLoop              = ", breakLoop);
            // console.log("=================================");
            

            console.log("iterations #", iterations);
            iterations += 1n;
            await mainInstance.connect(owner).claim(availableToClaim, charlie.address);

            totalClaimed += availableToClaim;
            await addNewHolderAndSwap({
                owner: owner,
                account: bob,
                buyPrice: buyPrice,
                lockupIntervalAmount: lockupIntervalAmount,
                mainInstance: mainInstance,
                buySellToken: buySellToken,
                uniswapRouterInstance: uniswapRouterInstance,
                erc20ReservedToken: erc20ReservedToken
            });
        }
        console.log("totalClaimed = ",totalClaimed/1_000_000_000_000_000_000n, " tokens");
        console.log("iterations = ",iterations);

        console.log("here");
    });        
});