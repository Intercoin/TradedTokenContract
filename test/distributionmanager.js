
const { expect } = require('chai');
const hre = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
require("@nomicfoundation/hardhat-chai-matchers");
// const chai = require('chai');
// const { time } = require('@openzeppelin/test-helpers');
const { deploy } = require("./fixtures/deploy.js");

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const DEAD_ADDRESS = '0x000000000000000000000000000000000000dEaD';
const UNISWAP_ROUTER_FACTORY_ADDRESS = '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f';
const UNISWAP_ROUTER = '0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D';

const ZERO = BigInt('0');
const ONE = BigInt('1');
const TWO = BigInt('2');
const THREE = BigInt('3');
const FOURTH = BigInt('4');
const FIVE = BigInt('5');
const SIX = BigInt('6');
const SEVEN = BigInt('7');
const EIGHT = BigInt('8');
const NINE = BigInt('9');
const TEN = BigInt('10');
const HUN = BigInt('100');
const THOUSAND = BigInt('1000');

const ONE_ETH = ethers.parseEther('1');

describe("DistributionManager", function () {
    
    describe("simple ERC20/ERC777 operations", function () {
        
        it("distributionManager should receive and transfer any erc20 tokens", async() => {

            const res = await loadFixture(deploy);
            const {
                owner,
                alice,
                externalTokenExchangePriceNumerator,
                externalTokenExchangePriceDenominator,
                claimFrequency,
                ERC20MintableF,
                ClaimManagerF,
                DistributionManagerF
            } = res;
            const nevermindToken = await ERC20MintableF.deploy("somename","somesymbol");
            const simpleerc20 = await ERC20MintableF.deploy("someERC20name","someERC20symbol");
            const claimManager = await ClaimManagerF.deploy(
                simpleerc20.target,
                [
                    nevermindToken.target,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );
            
            const distributionManager = await DistributionManagerF.connect(owner).deploy(
                nevermindToken.target, 
                claimManager.target
            );

            const amountToMint = ONE_ETH;
            const balanceBefore = await simpleerc20.balanceOf(distributionManager.target);
            const balanceAliceBefore = await simpleerc20.balanceOf(alice.address);

            await simpleerc20.mint(distributionManager.target, amountToMint);

            const balanceAfter = await simpleerc20.balanceOf(distributionManager.target);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter - balanceBefore
            );

            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await simpleerc20.balanceOf(alice.address);
            const balanceAfterSendOut = await simpleerc20.balanceOf(distributionManager.target);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter - balanceAliceBefore
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });

        it("distributionManager should receive and send any erc777 tokens", async() => {
            const res = await loadFixture(deploy);
            const {
                owner,
                alice,
                externalTokenExchangePriceNumerator,
                externalTokenExchangePriceDenominator,
                claimFrequency,
                ERC20MintableF,
                ERC777MintableF,
                ClaimManagerF,
                DistributionManagerF
            } = res;

            const nevermindToken = await ERC20MintableF.deploy("somename","somesymbol");
            const simpleerc777 = await ERC777MintableF.deploy();

            const claimManager = await ClaimManagerF.deploy(
                simpleerc777.target,
                [
                    nevermindToken.target,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );
            
            const distributionManager = await DistributionManagerF.connect(owner).deploy(
                nevermindToken.target, 
                claimManager.target
            );

            const amountToMint = ONE_ETH;
            const balanceBefore = await simpleerc777.balanceOf(distributionManager.target);
            const balanceAliceBefore = await simpleerc777.balanceOf(alice.address);

            await simpleerc777.mint(distributionManager.target, amountToMint);

            const balanceAfter = await simpleerc777.balanceOf(distributionManager.target);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter - balanceBefore
            );

            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await simpleerc777.balanceOf(alice.address);
            const balanceAfterSendOut = await simpleerc777.balanceOf(distributionManager.target);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter - balanceAliceBefore
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });
    });

    describe("tests with TradedToken", function () {
        
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
                liquidityLib,
                ERC20MintableF,
                ERC777MintableF,
                ClaimManagerF,
                DistributionManagerF,
                TradedTokenF
            } = res;

            const erc20ReservedToken  = await ERC20MintableF.deploy("ERC20 Reserved Token", "ERC20-RSRV");
            const externalToken       = await ERC20MintableF.deploy("ERC20 External Token", "ERC20-EXT");
            const erc20token          = await ERC20MintableF.deploy("ERC20Token", "ERC20T");
            const erc777token         = await ERC777MintableF.deploy();

            const tradedTokenInstance = await TradedTokenF.connect(owner).deploy(
                [
                    tokenName,
                    tokenSymbol,
                    erc20ReservedToken.target, //” (USDC)
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
                tradedTokenInstance.target,
                [
                    externalToken.target,
                    [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                    claimFrequency
                ]
            );

            const distributionManager = await DistributionManagerF.connect(owner).deploy(
                externalToken.target, 
                claimManager.target
            );

            return {...res, ...{
                distributionManager, 
                claimManager,
                erc20token, 
                erc777token, 
                externalToken,
                tradedTokenInstance, 
                erc20ReservedToken,
                liquidityLib,
                tradedTokenInstance,
                claimManager,
                distributionManager
            }};
        }

        it("distributionManager should receive and send TradedToken", async() => {
            const res = await loadFixture(deploy2);
            const {
                owner,
                alice,
                tradedTokenInstance,
                distributionManager
            } = res;

            const amountToMint = ONE_ETH;
            const balanceBefore = await tradedTokenInstance.balanceOf(distributionManager.target);
            const balanceAliceBefore = await tradedTokenInstance.balanceOf(alice.address);

            await tradedTokenInstance.mint(distributionManager.target, amountToMint);

            const balanceAfter = await tradedTokenInstance.balanceOf(distributionManager.target);
            
            expect(
                amountToMint
            ).to.be.eq(
                balanceAfter - balanceBefore
            );
            //--
            await tradedTokenInstance.connect(owner).addManager(distributionManager.target);
            //--
            await distributionManager.connect(owner).transfer(alice.address, amountToMint);

            const balanceAliceAfter = await tradedTokenInstance.balanceOf(alice.address);
            const balanceAfterSendOut = await tradedTokenInstance.balanceOf(distributionManager.target);

            expect(
                amountToMint
            ).to.be.eq(
                balanceAliceAfter - balanceAliceBefore
            );
            expect(balanceAfterSendOut).to.be.eq(ZERO);
        });

        it("distributionManager should call wantToClaim", async() => {
            const res = await loadFixture(deploy2);
            const {
                owner,
                claimManager,
                tradedTokenInstance,
                externalToken,
                distributionManager
            } = res;

            const claimAmount = ONE_ETH;
            var mapBefore = await claimManager.wantToClaimMap(distributionManager.target);

            await expect(distributionManager.connect(owner).wantToClaim(claimAmount)).to.be.revertedWithCustomError(tradedTokenInstance, "InsufficientAmount");
            await externalToken.mint(distributionManager.target, claimAmount);
            await distributionManager.connect(owner).wantToClaim(claimAmount);

            var mapAfter = await claimManager.wantToClaimMap(distributionManager.target);

            expect(mapBefore.amount).to.be.eq(ZERO);
            expect(mapAfter.amount).to.be.eq(claimAmount);
            
        });

        it("distributionManager should call claim", async() => {
            const res = await loadFixture(deploy2);
            const {
                owner,
                bob,
                claimFrequency,
                claimManager,
                tradedTokenInstance,
                externalToken,
                erc20ReservedToken,
                distributionManager
            } = res;

            const claimAmount = ONE_ETH;
            var bobBalanceBefore = await tradedTokenInstance.balanceOf(bob.address);
            
            await expect(distributionManager.connect(owner).wantToClaim(claimAmount)).to.be.revertedWithCustomError(tradedTokenInstance, "InsufficientAmount");
            await externalToken.mint(distributionManager.target, claimAmount);
            await distributionManager.connect(owner).wantToClaim(claimAmount);

            // try#1
            await expect(
                distributionManager.connect(owner).claim(claimAmount,bob.address)
            ).to.be.revertedWithCustomError(claimManager, 'ClaimTooFast');
            //pass time
            await time.increase(claimFrequency);

            // try#2
            await expect(
                distributionManager.connect(owner).claim(claimAmount,bob.address)
            ).to.be.revertedWithCustomError(tradedTokenInstance, 'EmptyReserves');
            //add reserves and initial liquidity
            await erc20ReservedToken.connect(owner).mint(tradedTokenInstance.target, ONE_ETH * THOUSAND);

            await tradedTokenInstance.connect(owner).addInitialLiquidity(ONE_ETH * TEN, ONE_ETH  * THOUSAND);

            // try#3
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWithCustomError(tradedTokenInstance, 'OwnerAndManagersOnly');
            // claimManager contract should be a manager on tradedToken
            await tradedTokenInstance.connect(owner).addManager(claimManager.target);

            // try#4
            await expect(distributionManager.connect(owner).claim(claimAmount,bob.address)).to.be.revertedWithCustomError(tradedTokenInstance, 'ClaimsDisabled');
            //-- need to enable claim mode 
            await tradedTokenInstance.connect(owner).enableClaims();
            
            // finally claim completely
            // and fix emission logic for test purpose
            
            await tradedTokenInstance.setEmissionPeriod(1);
            await tradedTokenInstance.setEmissionAmount(ethers.parseEther('10000'));

            await distributionManager.connect(owner).claim(claimAmount,bob.address);
            var bobBalanceAfter = await tradedTokenInstance.balanceOf(bob.address);

            expect(ZERO).to.be.eq(bobBalanceBefore);
            expect(claimAmount).to.be.eq(bobBalanceAfter - bobBalanceBefore);

        });

    });


    
    
})