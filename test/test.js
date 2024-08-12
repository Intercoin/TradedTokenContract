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

describe("TradedTokenInstance", function () {
    describe("validate params", function () {
        it("should correct reserveToken", async() => {
            const {
                owner,
                tokenName,
                tokenSymbol,
                TradedTokenF,
                priceDrop,
                lockupIntervalAmount,
                minClaimPriceNumerator, minClaimPriceDenominator,
                minClaimPriceGrowNumerator, minClaimPriceGrowDenominator,
                taxesInfo,
                RateLimitDuration, RateLimitValue,
                StructTaxes,
                StructBuySellPrice,
                emissionAmount,
                emissionFrequency,
                emissionPeriod,
                emissionDecrease,
                emissionPriceGainMinimum,
                durationSendBack,
                liquidityLib
            } = await loadFixture(deploy);

            await expect(
                TradedTokenF.connect(owner).deploy(
                    [
                        tokenName,
                        tokenSymbol,
                        constants.ZERO_ADDRESS, //” (USDC)
                        priceDrop,
                        lockupIntervalAmount,
                        durationSendBack
                    ],
                    [
                        [minClaimPriceNumerator, minClaimPriceDenominator],
                        [minClaimPriceGrowNumerator, minClaimPriceGrowDenominator]
                    ],
                    taxesInfo,
                    [RateLimitDuration, RateLimitValue],
                    StructTaxes,
                    StructBuySellPrice,
                    //emission
                    [
                        emissionAmount,
                        emissionFrequency,
                        emissionPeriod,
                        emissionDecrease,
                        emissionPriceGainMinimum
                    ],
                    liquidityLib.target
                )
            ).to.be.revertedWithCustomError(TradedTokenF, "ReserveTokenInvalid");
        });

    });

    describe("instance check", function () {

        it("shouldn't setup empty address as traded token", async() => {
            const {
                externalTokenExchangePriceNumerator, 
                externalTokenExchangePriceDenominator,
                claimFrequency,
                externalToken,
                ClaimManagerF,
                ClaimManagerFactory
            } = await loadFixture(deploy2);

            await expect(
                ClaimManagerFactory.produce(
                    constants.ZERO_ADDRESS,
                    [
                        externalToken.target,
                        [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                        claimFrequency
                    ]
                )
            ).to.be.revertedWithCustomError(ClaimManagerF, "EmptyTokenAddress");
        });

        it("shouldn't setup empty address as external token", async() => {
            const {
                externalTokenExchangePriceNumerator, 
                externalTokenExchangePriceDenominator,
                claimFrequency,
                mainInstance,
                ClaimManagerF,
                ClaimManagerFactory
            } = await loadFixture(deploy2);

            await expect(
                ClaimManagerFactory.produce(
                    mainInstance.target,
                    [
                        constants.ZERO_ADDRESS,
                        [externalTokenExchangePriceNumerator, externalTokenExchangePriceDenominator],
                        claimFrequency
                    ]
                )
            ).to.be.revertedWithCustomError(ClaimManagerF, "EmptyTokenAddress");
        });

        it("reverted if didn't add liquidity before", async() => {
            const {
                mainInstance,
                internalLiquidity
            } = await loadFixture(deploy2);

            await expect(
                mainInstance.availableToClaim()
            ).to.be.revertedWithCustomError(internalLiquidity, 'EmptyReserves');
        });
        
        it("should valid ClamedEnabledTime", async() => {
            const {
                owner,
                bob,
                mainInstance
            } = await loadFixture(deploy2);

            expect(await mainInstance.claimsEnabledTime()).to.be.eq(0);
            await expect(mainInstance.connect(bob).enableClaims()).revertedWith("Ownable: caller is not the owner");
            await mainInstance.connect(owner).enableClaims();
            expect(await mainInstance.claimsEnabledTime()).not.to.be.eq(0n);
            await expect(mainInstance.connect(owner).enableClaims()).revertedWithCustomError(mainInstance, "ClaimsEnabledTimeAlreadySetup");
        });

        it("cover sqrt func", async() => {
            const {
                mainInstance
            } = await loadFixture(deploy2);
            expect(await mainInstance.getSqrt(0)).to.be.equal(0);
            expect(await mainInstance.getSqrt("0x100000000000000000000000000000000")).to.be.equal("0x10000000000000000");
            expect(await mainInstance.getSqrt("0x10000000000000000")).to.be.equal("0x100000000");
            expect(await mainInstance.getSqrt("0x100000000")).to.be.equal("0x10000");
            expect(await mainInstance.getSqrt("0x10000")).to.be.equal("0x100");
            expect(await mainInstance.getSqrt("0x100")).to.be.equal("0x10");
        });

        it("should correct Intercoin Investor Token", async() => {
            const {
                tokenName,
                mainInstance
            } = await loadFixture(deploy2);
            expect(await mainInstance.name()).to.be.equal(tokenName);
        });

        it("should correct ITR", async() => {
            const {
                tokenSymbol,
                mainInstance
            } = await loadFixture(deploy2);
            expect(await mainInstance.symbol()).to.be.equal(tokenSymbol);
        });

        it("shouldnt `addLiquidity` without liquidity", async() => {
            const {
                owner,
                mainInstance
            } = await loadFixture(deploy2);

            await expect(
                mainInstance.connect(owner).addLiquidity(ethers.parseEther('1'))
            ).to.be.revertedWithCustomError(mainInstance, "InitialLiquidityRequired");
        }); 

        it("shouldnt addLiquidity manually without method `addInitialLiquidity`", async() => {
            const {
                bob,
                erc20ReservedToken,
                mainInstance
            } = await loadFixture(deploy2);

            const uniswapRouter = await mainInstance.getUniswapRouter();
            let uniswapRouterInstance = await ethers.getContractAt("IUniswapV2Router02", uniswapRouter);

            
            await erc20ReservedToken.mint(bob.address, ethers.parseEther('1'));
            await mainInstance.mint(bob.address, ethers.parseEther('1'));

            await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('1'));
            await mainInstance.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('1'));

            let ts = await time.latest();
            let timeUntil = parseInt(ts)+parseInt(8n*24n*60n*60n);

            // handle TransferHelper error although it's happens in our contract
            await expect(
                uniswapRouterInstance.connect(bob).addLiquidity(
                    mainInstance.target, //address tokenA,
                    erc20ReservedToken.target, //address tokenB,
                    ethers.parseEther('1'), //uint amountADesired,
                    ethers.parseEther('1'), //uint amountBDesired,
                    ethers.parseEther('1'), //uint amountAMin,
                    ethers.parseEther('1'), //uint amountBMin,
                    bob.address, //address to,
                    timeUntil //uint deadline
                )
            ).to.be.revertedWith("TransferHelper: TRANSFER_FROM_FAILED");
        }); 

        it("should add managers", async() => {
            const {
                owner,
                bob,
                charlie,
                mainInstance
            } = await loadFixture(deploy2);

            await expect(
                mainInstance.connect(bob).addManager(charlie.address)
            ).to.be.revertedWith("Ownable: caller is not the owner");

            expect(await mainInstance.connect(owner).managers(bob.address)).to.be.eq(0);
            await mainInstance.connect(owner).addManager(bob.address);
            expect(await mainInstance.connect(owner).managers(bob.address)).not.to.be.eq(0);

            await expect(
                mainInstance.connect(bob).addManager(charlie.address)
            ).to.be.revertedWith("Ownable: caller is not the owner");
        });

        it("should remove managers", async() => {
            const {
                owner,
                alice,
                bob,
                mainInstance
            } = await loadFixture(deploy2);

            await mainInstance.connect(owner).addManager(alice.address);

            await expect(
                mainInstance.connect(bob).removeManagers([alice.address])
            ).to.be.revertedWith("Ownable: caller is not the owner");

            await mainInstance.connect(owner).addManager(bob.address);
            await expect(
                mainInstance.connect(bob).removeManagers([alice.address])
            ).to.be.revertedWith("Ownable: caller is not the owner");

            expect(await mainInstance.connect(owner).managers(alice.address)).not.to.be.eq(0);
            await mainInstance.connect(owner).removeManagers([alice.address])
            expect(await mainInstance.connect(owner).managers(alice.address)).to.be.eq(0);            
        });

        it("[cover] shouldnt claim (ClaimValidationError)", async() => {
          const {
                owner,
                bob,
                erc20ReservedToken,
                internalLiquidity,
                mainInstance
            } = await loadFixture(deploy2);

            await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));
            await mainInstance.addInitialLiquidity(ethers.parseEther('1000'), ethers.parseEther('10'));
            await mainInstance.forceSync();
                
            await mainInstance.connect(owner).enableClaims();

            // make synthetic  situation when totalCumulativeAmount are small
            await mainInstance.connect(owner).setTotalCumulativeClaimed(1n);
            await expect(
                mainInstance.connect(owner).claim(1n, bob.address)
            ).to.be.revertedWithCustomError(internalLiquidity, "ClaimValidationError");
        });   

        describe("presale", function () {
            it("shouldnt presale if caller is not owner", async() => {
                const {
                    bob,
                    timeUntil,
                    Presale,
                    mainInstance
                } = await loadFixture(deployInPresale);

                await expect(
                    mainInstance.connect(bob).startPresale(Presale.target, ethers.parseEther('1'), timeUntil)
                ).to.be.revertedWith("Ownable: caller is not the owner");
            });
 
            it("should burn after presale end", async() => {
                
                const {
                    owner,
                    timeUntil,
                    lockupIntervalAmount,
                    Presale,
                    mainInstance
                } = await loadFixture(deployInPresale);

                await Presale.setEndTime(timeUntil);

                const tokenBefore = await mainInstance.balanceOf(Presale.target);
                await mainInstance.connect(owner).startPresale(Presale.target, ethers.parseEther('1'), 24n*60n*60n);
                const tokenAfter = await mainInstance.balanceOf(Presale.target);

                expect(tokenBefore).to.be.eq(0);
                expect(tokenAfter).to.be.eq(ethers.parseEther('1'));
                
                // can be burn in the end( before an hour the endTime)
                await mainInstance.connect(owner).burnRemaining(Presale.target);
                const tokenAfter2 = await mainInstance.balanceOf(Presale.target);
                expect(tokenAfter2).to.be.eq(tokenAfter);

                // pass in the end
                await network.provider.send("evm_increaseTime", [parseInt(lockupIntervalAmount*24n*60n*60n)]);
                await network.provider.send("evm_mine");

                const tokenBefore3 = await mainInstance.balanceOf(Presale.target);
                await mainInstance.connect(owner).burnRemaining(Presale.target);
                const tokenAfter3 = await mainInstance.balanceOf(Presale.target);

                expect(tokenBefore3).to.be.eq(ethers.parseEther('1'));
                expect(tokenAfter3).to.be.eq(0);

                // also try to burn after burning)
                await mainInstance.connect(owner).burnRemaining(Presale.target);
                const tokenAfter4 = await mainInstance.balanceOf(Presale.target);
                expect(tokenAfter4).to.be.eq(0);

            });

            it("should presale", async() => {
                const {
                    owner,
                    bob,
                    timeUntil,
                    lockupIntervalDay,
                    Presale,
                    mainInstance
                } = await loadFixture(deployInPresale);

                await Presale.setEndTime(timeUntil);

                await mainInstance.connect(owner).startPresale(Presale.target, ethers.parseEther('1'), lockupIntervalDay);

                const amountSend = ethers.parseEther('0.1');
                const lockedBefore = await mainInstance.getLockedAmount(bob.address);
                const lockedPresaleBefore = await mainInstance.getLockedAmount(Presale.target);

                // imitation presale operations
                let tx = await Presale.transferTokens(mainInstance.target, bob.address, amountSend);

                const lockedAfter = await mainInstance.getLockedAmount(bob.address);
                const lockedPresaleAfter = await mainInstance.getLockedAmount(Presale.target);

                const DAY = 24n*60n*60n;
                const rc = await tx.wait();

                const block = await ethers.provider.getBlock(rc.blockNumber);
                const blockTimestamp = BigInt(block.timestamp)
                const startTs = blockTimestamp / DAY * DAY;

                const timePassed = blockTimestamp - startTs;
                const speed = amountSend / (lockupIntervalDay * DAY);
                const expectLocked = amountSend - (speed * timePassed);
                
                expect(lockedBefore).to.be.eq(0);
                expect(lockedPresaleBefore).to.be.eq(0);
                expect(lockedPresaleAfter).to.be.eq(0);

                // floating point in js. So didnt check last six-seven digits/ for the numbers like below
                // lockedAfter  = BigInt('53031249999981333');
                // expectLocked = BigInt('53031250000016533');
                // console.log(lockedAfter.toString());
                // console.log(expectLocked.toString());
                expect(
                    lockedAfter/10000000n*10000000n
                ).to.be.eq(
                    expectLocked/10000000n*10000000n
                );
            });

            describe("shouldnt presale if Presale contract invalid", function () {
                it(" --- zero address", async() => {
                    const {
                        owner,
                        timeUntil,
                        mainInstance
                    } = await loadFixture(deployInPresale);

                    await expect(
                        mainInstance.connect(owner).startPresale(constants.ZERO_ADDRESS, ethers.parseEther('1'), timeUntil)
                    ).to.be.revertedWithCustomError(mainInstance, 'EmptyAddress');
                });

                it(" --- eoa address", async() => {
                    const {
                        owner,
                        bob,
                        timeUntil,
                        mainInstance
                    } = await loadFixture(deployInPresale);
                    
                    await expect(
                        mainInstance.connect(owner).startPresale(bob.address, ethers.parseEther('1'), timeUntil)
                    ).to.be.reverted;//revertedWith('function returned an unexpected amount of data');
                });

                it(" --- without endTime method", async() => {
                    const {
                        owner,
                        timeUntil,
                        mainInstance
                    } = await loadFixture(deployInPresale);
                    
                    const PresaleBad1F = await ethers.getContractFactory("PresaleBad1");
                    let presaleBad1 = await PresaleBad1F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad1.target, ethers.parseEther('1'), timeUntil)
                    ).to.be.reverted;//revertedWith("function selector was not recognized and there's no fallback function");
                });

                it(" --- endTime have wrong output", async() => {
                    const {
                        owner,
                        timeUntil,
                        mainInstance
                    } = await loadFixture(deployInPresale);

                    const PresaleBad2F = await ethers.getContractFactory("PresaleBad2");
                    let presaleBad2 = await PresaleBad2F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad2.target, ethers.parseEther('1'), timeUntil)
                    ).to.be.reverted;//revertedWith("function selector was not recognized and there's no fallback function");

                });

                it(" --- fallback method only", async() => {
                    const {
                        owner,
                        timeUntil,
                        mainInstance
                    } = await loadFixture(deployInPresale);

                    const PresaleBad3F = await ethers.getContractFactory("PresaleBad3");
                    let presaleBad3 = await PresaleBad3F.deploy();

                    await expect(
                        mainInstance.connect(owner).startPresale(presaleBad3.target, ethers.parseEther('1'), timeUntil)
                    ).to.be.reverted;//revertedWith('function returned an unexpected amount of data');
                });
            });
        }); 

        describe("claim", function () {
            it("required InitialLiquidity", async() => {
                const res = await loadFixture(deploy2);
                const {
                    owner,
                    mainInstance,
                    erc20ReservedToken
                } = res;

                await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));

                await expect(
                    mainInstance.connect(owner).addLiquidity(ethers.parseEther('1'))
                ).to.be.revertedWithCustomError(mainInstance, "InitialLiquidityRequired");
            });

            it("addInitialLiquidity should be called by owners or managers", async() => {
                const res = await loadFixture(deploy2);
                const {
                    owner,
                    charlie,
                    erc20ReservedToken,
                    mainInstance
                } = res;

                await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));

                await expect(
                    mainInstance.connect(charlie).addInitialLiquidity(ethers.parseEther('10'), ethers.parseEther('10'))
                ).to.be.revertedWithCustomError(mainInstance, "OwnerAndManagersOnly");
            });

            it("shouldnt add initial liquidity twice", async() => {
                const res = await loadFixture(deploy2);
                const {
                    owner,
                    erc20ReservedToken,
                    mainInstance
                } = res;

                await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));
                await mainInstance.connect(owner).addInitialLiquidity(ethers.parseEther('10'), ethers.parseEther('10'));
                await expect(
                    mainInstance.connect(owner).addInitialLiquidity(ethers.parseEther('10'), ethers.parseEther('10'))
                ).to.be.revertedWithCustomError(mainInstance, "AlreadyCalled");
            });

            it("shouldnt presale already added liquidity", async() => {
                const res = await loadFixture(deploy2);
                const {
                    owner,
                    alice,
                    lockupIntervalAmount,
                    erc20ReservedToken,
                    mainInstance
                } = res;

                await erc20ReservedToken.connect(owner).mint(mainInstance.target, ethers.parseEther('10'));
                await mainInstance.connect(owner).addInitialLiquidity(ethers.parseEther('10'), ethers.parseEther('10'));

                const ts = await time.latest();
                const timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                await expect(
                    mainInstance.connect(owner).startPresale(alice.address, ethers.parseEther('1'), timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, "BeforeInitialLiquidityRequired");
            });


            describe("after adding liquidity", function () {
                it("shouldnt claim if claimingTokenAmount == 0", async() => {
                    const res = await loadFixture(deploy3);
                    const {
                        owner,
                        bob,
                        claimManager,
                        internalLiquidity,
                        mainInstance
                    } = res;

                    await expect(
                        claimManager.connect(bob).claim(0, bob.address)
                    ).to.be.revertedWithCustomError(claimManager, "InputAmountCanNotBeZero");

                    // by owner
                    await mainInstance.connect(owner).enableClaims();
                    await expect(
                        mainInstance.connect(owner).claim(0, owner.address)
                    ).to.be.revertedWithCustomError(internalLiquidity, "InputAmountCanNotBeZero");
                });

                it("shouldnt claim with empty address", async() => {
                    const res = await loadFixture(deploy3);
                    const {
                        owner,
                        internalLiquidity,
                        mainInstance
                    } = res;

                    await mainInstance.connect(owner).enableClaims();
                    await expect(
                        mainInstance.connect(owner).claim(ethers.parseEther('1'), constants.ZERO_ADDRESS)
                    ).to.be.revertedWithCustomError(internalLiquidity, "EmptyAccountAddress");
                });
                
                it("shouldnt call restrictClaiming by owner", async() => {
                    const {
                        owner,
                        mainInstance
                    } = await loadFixture(deploy3);
                    
                    await expect(
                        mainInstance.connect(owner).restrictClaiming([ethers.parseEther('1'), 1])
                    ).to.be.revertedWithCustomError(mainInstance, "ManagersOnly");
                });

                it("shouldnt setup zero denominator", async() => {
                    const {
                        owner,
                        bob,
                        mainInstance
                    } = await loadFixture(deploy3);
                    
                    await expect(
                        mainInstance.connect(bob).restrictClaiming([ethers.parseEther('1'), 1])
                    ).to.be.revertedWithCustomError(mainInstance, "ManagersOnly");

                    await mainInstance.connect(owner).addManager(bob.address);
                    await expect(
                        mainInstance.connect(bob).restrictClaiming([ethers.parseEther('1'), 0])
                    ).to.be.revertedWithCustomError(mainInstance, "ZeroDenominator");
                });

                it("shouldnt price grow too fast", async() => {
                    const {
                        owner,
                        bob,
                        internalLiquidity,
                        mainInstance
                    } = await loadFixture(deploy3);

                    await mainInstance.connect(owner).addManager(bob.address);
                    await expect(
                        mainInstance.connect(bob).restrictClaiming([1n, 100n])
                    ).to.be.revertedWithCustomError(internalLiquidity, "MinClaimPriceGrowTooFast");
                });

                it("shouldnt price less than setup before", async() => {
                    const {
                        owner,
                        bob,
                        minClaimPriceNumerator, 
                        minClaimPriceDenominator,
                        internalLiquidity,
                        mainInstance
                    } = await loadFixture(deploy3);

                    await mainInstance.connect(owner).addManager(bob.address);

                    let minClaimPriceUpdatedTime = await mainInstance.getMinClaimPriceUpdatedTime();
                    
                    await time.increase(parseInt(minClaimPriceUpdatedTime));

                    await expect(
                        mainInstance.connect(bob).restrictClaiming([minClaimPriceNumerator, minClaimPriceDenominator + 1n])
                    ).to.be.revertedWithCustomError(internalLiquidity, "ShouldBeMoreThanMinClaimPrice");
                });

                describe("some validate", function () {
                    it("price has not become a lower than minClaimPrice ", async() => {
                        const {
                            owner,
                            alice,
                            bob,
                            charlie,
                            claimFrequency,
                            buyPrice,
                            claimManager,
                            externalToken,
                            erc20ReservedToken,
                            lockupIntervalAmount,
                            buySellToken,
                            internalLiquidity,
                            uniswapRouterInstance,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                        const tokensToClaim = ethers.parseEther('400');
                        await mainInstance.setEmissionAmount(tokensToClaim);
                        await mainInstance.connect(owner).addManager(claimManager.target);

                        

                        // pass time to clear bucket
                        await time.increase(claimFrequency);
            
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: alice,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });
                        
                        
                        await externalToken.connect(owner).mint(charlie.address, tokensToClaim);
                        await externalToken.connect(charlie).approve(claimManager.target, tokensToClaim);
                        await claimManager.connect(charlie).wantToClaim(tokensToClaim);
                        
                        // pass time after wantToClaim
                        await time.increase(claimFrequency);

                        // dev note:
                        // Keep in mind that claimManager simply calls the `availableToClaim` method and gets zero.
                        // "PriceMayBecomeLowerThanMinClaimPrice" refers to a custom error in the mainInstance.
                        // The claimManager prevents calling a transaction with incorrect arguments.
                        await expect(
                            claimManager.connect(charlie).claim(tokensToClaim, charlie.address)
                        ).to.be.revertedWithCustomError(claimManager, "InsufficientAmountToClaim").withArgs(tokensToClaim, 0);

                        //if we will try to call claim directly(avoid claimmanager) we will handle "PriceMayBecomeLowerThanMinClaimPrice"
                        await externalToken.connect(charlie).approve(mainInstance.target, tokensToClaim);
                        await expect(
                            mainInstance.connect(owner).claim(tokensToClaim, charlie.address)
                        ).to.be.revertedWithCustomError(internalLiquidity, "PriceMayBecomeLowerThanMinClaimPrice");
                    });

                    it("shouldnt claim if claimTime == 0 (disabled)", async() => {
                        const {
                            owner,
                            bob,
                            charlie,
                            claimFrequency,
                            buyPrice,
                            claimManager,
                            externalToken,
                            erc20ReservedToken,
                            lockupIntervalAmount,
                            buySellToken,
                            uniswapRouterInstance,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettings);

                        const expectedTokens = ethers.parseEther("1");
                        const calculatedBuySellTokensAmount = expectedTokens * FRACTION / buyPrice;
                        // buy 
                        await buySellToken.connect(owner).mint(bob.address, calculatedBuySellTokensAmount);
                        await buySellToken.connect(bob).approve(mainInstance.target, calculatedBuySellTokensAmount);
                        await mainInstance.connect(bob).buy(expectedTokens);

                        // then swap
                        const reserveTokenToSwap = ethers.parseEther("0.5");
                        await erc20ReservedToken.connect(owner).mint(bob.address, reserveTokenToSwap);
                        await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, reserveTokenToSwap);
                        var ts = await time.latest();
                        var timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                        await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                            reserveTokenToSwap, //uint amountIn,
                            0, //uint amountOutMin,
                            [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                            bob.address, //address to,
                            timeUntil //uint deadline   
                        );

                        const tokensToClaim = await mainInstance.connect(owner).availableToClaim();
                        await externalToken.connect(owner).mint(charlie.address, tokensToClaim);
                        await externalToken.connect(charlie).approve(claimManager.target, tokensToClaim);
                        await claimManager.connect(charlie).wantToClaim(tokensToClaim);
                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await mainInstance.connect(owner).addManager(claimManager.target);
                        //-------------------------------
                        await expect(
                            claimManager.connect(charlie).claim(tokensToClaim, bob.address)
                        ).to.be.revertedWithCustomError(mainInstance, "ClaimsDisabled");
                    });
                });

                describe("mint and approve", function () {
                    it("shouldnt claim if claimingTokenAmount more than allowance", async() => {
                        const {
                            bob,
                            claimManager,
                            mainInstance
                        } = await loadFixture(deploy4);

                        await expect(
                            claimManager.connect(bob).claim(ethers.parseEther('2'), bob.address)
                        ).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                    });
                    
                    it("shouldnt wantToClaim if amount more that available", async() => {
                        const {
                            bob,
                            claimManager,
                            mainInstance
                        } = await loadFixture(deploy4);

                        await expect(
                            claimManager.connect(bob).wantToClaim(ethers.parseEther('100'))
                        ).to.be.revertedWithCustomError(mainInstance, `InsufficientAmount`);
                    });

                    it("shouldnt claim too fast", async() => {
                        const {
                            bob,
                            claimFrequency,
                            claimManager
                        } = await loadFixture(deploy4);

                        const lastActionTs = await claimManager.getLastActionTime(bob.address);
                        await expect(
                            claimManager.connect(bob).claim(ethers.parseEther('1'), bob.address)
                        ).to.be.revertedWithCustomError(claimManager, 'ClaimTooFast').withArgs(lastActionTs + claimFrequency);
                    });   

                    
                    it("shouldnt claim if didnt wantClaim before", async() => {
                        const {
                            bob,
                            claimFrequency,
                            claimManager
                        } = await loadFixture(deploy4);

                        // pass time to clear bucket
                        await time.increase(claimFrequency);

                        await expect(
                            claimManager.connect(bob).claim(ethers.parseEther('1'), bob.address)
                        ).to.be.revertedWithCustomError(claimManager, 'InsufficientAmountToClaim').withArgs(ethers.parseEther('1'), 0);
                    });


                    describe("call wantToClaim", function () {
                        it("shouldnt claim if claimManager is not a manager for TradedToken ", async() => {
                            const {
                                owner,
                                bob,
                                claimFrequency,
                                claimManager,
                                externalToken,
                                mainInstance
                            } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                            //minting to bob and approve
                            await externalToken.connect(owner).mint(bob.address, ethers.parseEther('1'));
                            await externalToken.connect(bob).approve(claimManager.target, ethers.parseEther('1'));

                            await claimManager.connect(bob).wantToClaim(ethers.parseEther('1'));
                            // // pass time to clear bucket
                            await time.increase(claimFrequency);

                            await expect(
                                claimManager.connect(bob).claim(ethers.parseEther('1'), bob.address)
                            ).to.be.revertedWithCustomError(mainInstance, `OwnerAndManagersOnly`);
        
                        });

                        describe("make claimManager as a manager", function () {
                            it("should claim", async() => {
                                const {
                                    owner,
                                    bob,
                                    david,
                                    claimFrequency,
                                    claimManager,
                                    externalToken,
                                    mainInstance
                                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                                //minting to bob and approve
                                await externalToken.connect(owner).mint(bob.address, ethers.parseEther('1'));
                                await externalToken.connect(bob).approve(claimManager.target, ethers.parseEther('1'));

                                await claimManager.connect(bob).wantToClaim(ethers.parseEther('1'));
                                // // pass time to clear bucket
                                await time.increase(claimFrequency);


                                await mainInstance.connect(owner).addManager(claimManager.target);
                                const balanceBefore = await mainInstance.balanceOf(bob.address);
                                await claimManager.connect(bob).claim(ethers.parseEther('1'), bob.address);
                                const balanceAfter = await mainInstance.balanceOf(bob.address);

                                expect(balanceAfter-balanceBefore).to.be.eq(ethers.parseEther('1'));
                                
                            });
                            it("when PriceGain more then minPriceGain - availableToClaim should be zero after !changes bucket!", async() => {
                                const {
                                    owner,
                                    bob,
                                    charlie,
                                    //claimFrequency,
                                    lockupIntervalAmount,
                                    uniswapRouterInstance,
                                    erc20ReservedToken,
                                    mainInstance
                                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);
                                await mainInstance.setEmissionFrequency(86400n);

                                let availableToClaim;

                                // FOR TEST make hte following things
                                // Bob - should be a manager = only managers can claim. actually this is should be a contract
                                await mainInstance.connect(owner).addManager(bob.address);
                                // Charlie - shoudl be a Community, because only community can send to exchanges
                                await mainInstance.connect(owner).setGovernor(bob.address);
                                await mainInstance.connect(bob).communitiesAdd(charlie.address, 1000n);
                                // Also Bob - should be a exchange, because common user can send back to exchanges only those tokens which was received from exchange
                                await mainInstance.connect(bob).exchangesAdd(bob.address, 1000n);

                                availableToClaim = await mainInstance.availableToClaim();
                                await mainInstance.connect(bob).claim(availableToClaim, charlie.address);
                                // // // pass time to clear bucket
                                // await time.increase(86400n);

                                // availableToClaim = await mainInstance.availableToClaim();
                                // await mainInstance.connect(bob).claim(availableToClaim, charlie.address);
                                
                                //let balanceCharlie =  await mainInstance.balanceOf(charlie.address);
                                let toSwap = availableToClaim//;balanceCharlie/20n;
                                await mainInstance.connect(charlie).approve(uniswapRouterInstance.target, toSwap);

                                let ts = await time.latest();
                                let timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                                //swapExactTokensForTokensSupportingFeeOnTransferTokens
                                //swapExactTokensForTokens

                                await uniswapRouterInstance.connect(charlie).swapExactTokensForTokens(
                                    toSwap, //uint amountIn,
                                    0, //uint amountOutMin,
                                    [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                                    charlie.address, //address to,
                                    timeUntil //uint deadline   
                                );

                                var customPriceGainMinimum = 8000n;
                                let currentPriceGain;

                                await mainInstance.setEmissionPriceGainMinimum(customPriceGainMinimum);
                                await time.increase(86400n);
                                availableToClaim = await mainInstance.availableToClaim();
                                //await mainInstance.connect(bob).claim(availableToClaim, charlie.address);
                                currentPriceGain = await mainInstance.getCurrentPriceGain();
                                expect(availableToClaim).to.be.eq(0n);
                                expect(currentPriceGain).lt(customPriceGainMinimum);

                                await time.increase(86400n);

                                availableToClaim = await mainInstance.availableToClaim();
                                expect(availableToClaim).to.be.eq(0n);
                                //await mainInstance.connect(bob).claim(availableToClaim, charlie.address);

                                await mainInstance.updateAveragePrice();
                                // here keep previuos state

                                await time.increase(86400n);
                                await mainInstance.updateAveragePrice();
                                //and now pricegain turn to 0
                                currentPriceGain = await mainInstance.getCurrentPriceGain();
                                expect(currentPriceGain).to.be.eq(0n);
                                

                            });

                            it("[cover] available to claim == 0", async() => {
                                
                                // const res = await loadFixture(deploy5);
                                // const {
                                //     owner,
                                //     mainInstance
                                // } = res;

                                // var emissionAmount = ethers.parseEther('1');
                                // await mainInstance.setEmissionAmount(emissionAmount);
                                // await mainInstance.setEmissionPeriod(86400n);
                                
                                // let availableToClaim = await mainInstance.availableToClaim();
                                // expect(availableToClaim).to.be.eq(emissionAmount);

                                const {
                                    owner,
                                    bob,
                                    david,
                                    claimFrequency,
                                    claimManager,
                                    externalToken,
                                    mainInstance
                                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                                //var emissionAmount = ethers.parseEther('1');
                                //await mainInstance.setEmissionAmount(emissionAmount);
                                //await mainInstance.setEmissionPeriod(86400n);
                                await mainInstance.setEmissionFrequency(86400n);
                                
                                let availableToClaim = await mainInstance.availableToClaim();

                                //minting to bob and approve
                                await externalToken.connect(owner).mint(bob.address, availableToClaim);
                                await externalToken.connect(bob).approve(claimManager.target, availableToClaim);

                                await claimManager.connect(bob).wantToClaim(availableToClaim);
                                // // pass time to clear bucket
                                await time.increase(86400n);
                                
                                await mainInstance.connect(owner).addManager(claimManager.target);

                                await claimManager.connect(bob).claim(availableToClaim, bob.address);
                                availableToClaim = await mainInstance.availableToClaim();
                                expect(availableToClaim).to.be.eq(0n);

                            });

                            it("should transfer to dead-address tokens after user claim", async() => {
                                const {
                                    owner,
                                    bob,
                                    claimFrequency,
                                    claimManager,
                                    externalToken,
                                    mainInstance
                                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                                //minting to bob and approve
                                await externalToken.connect(owner).mint(bob.address, ethers.parseEther('1'));
                                await externalToken.connect(bob).approve(claimManager.target, ethers.parseEther('1'));

                                await claimManager.connect(bob).wantToClaim(ethers.parseEther('1'));
                                // // pass time to clear bucket
                                await time.increase(claimFrequency);

                                await mainInstance.connect(owner).addManager(claimManager.target);

                                const tokensToClaim = ethers.parseEther('1');
                                const tokensBefore = await externalToken.balanceOf(DEAD_ADDRESS);
                                await claimManager.connect(bob).claim(tokensToClaim, bob.address);
                                const tokensAfter = await externalToken.balanceOf(DEAD_ADDRESS);
                                expect(tokensBefore + tokensToClaim).to.be.eq(tokensAfter);
                            });

                            it("should claim (scale 1:2 applying) ", async() => {
                                const {
                                    owner,
                                    bob,
                                    charlie,
                                    claimFrequency,
                                    claimManager,
                                    externalToken,
                                    mainInstance
                                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                                await mainInstance.connect(owner).addManager(claimManager.target);
                                
                                let availableToClaim = await mainInstance.availableToClaim();
 
                                //await externalToken.connect(owner).mint(bob.address, userWantToClaim);
                                await externalToken.connect(owner).mint(charlie.address, availableToClaim * 2n);
                                await externalToken.connect(charlie).approve(claimManager.target, availableToClaim * 2n);

                                //minting to bob and approve
                                await externalToken.connect(owner).mint(bob.address, availableToClaim);
                                await externalToken.connect(bob).approve(claimManager.target, availableToClaim);

                                let bobExternalTokenBalanceBefore = await externalToken.balanceOf(bob.address);
                                let bobTradedTokenBalanceBefore = await mainInstance.balanceOf(bob.address);
                                let mainInstanceExternalTokenBalanceBefore = await externalToken.balanceOf(mainInstance.target);

                                // two users want to get all available amount of tokens
                                let wantToClaimTotal = 0n;
                                await claimManager.connect(bob).wantToClaim(availableToClaim);
                                wantToClaimTotal = wantToClaimTotal + availableToClaim;
                                await claimManager.connect(charlie).wantToClaim(availableToClaim * 2n);
                                wantToClaimTotal = wantToClaimTotal + (availableToClaim * 2n);

                                // pass time 
                                await time.increase(claimFrequency);

                                await expect(
                                    claimManager.connect(bob).claim(availableToClaim, bob.address)
                                ).to.be.revertedWithCustomError(claimManager, 'InsufficientAmountToClaim').withArgs(availableToClaim, availableToClaim * availableToClaim / wantToClaimTotal);

                                let scaledAmount = availableToClaim * availableToClaim / wantToClaimTotal;
                                await claimManager.connect(bob).claim(scaledAmount, bob.address);

                                let bobExternalTokenBalanceAfter = await externalToken.balanceOf(bob.address);
                                let mainInstanceExternalTokenBalanceAfter = await externalToken.balanceOf(mainInstance.target);
                                let bobTradedTokenBalanceAfter = await mainInstance.balanceOf(bob.address);

                                expect(bobTradedTokenBalanceAfter - bobTradedTokenBalanceBefore).to.be.eq(scaledAmount);
                                expect(bobExternalTokenBalanceBefore - bobExternalTokenBalanceAfter).to.be.eq(scaledAmount);
                                expect(mainInstanceExternalTokenBalanceAfter - mainInstanceExternalTokenBalanceBefore).to.be.eq(0);

                                //await ethers.provider.send('evm_revert', [snapId]);
                            });
                        });
                    });
                });
                
                describe("internal", function () {
                    it("shouldnt locked up tokens after owner claim", async() => {
                        const {
                            owner,
                            alice,
                            bob,
                            charlie,
                            claimFrequency,
                            buyPrice,
                            lockupIntervalAmount,
                            buySellToken,
                            erc20ReservedToken,
                            uniswapRouterInstance,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                        //----
                        const ONE_ETH = ethers.parseEther('1');
                        
                        const bobTokensBefore = await mainInstance.balanceOf(bob.address);
                        const aliceTokensBefore = await mainInstance.balanceOf(alice.address);

                        await mainInstance.connect(owner).claim(ONE_ETH, owner.address);

                        await mainInstance.connect(owner).transfer(alice.address,ONE_ETH);
                        // pass time to clear bucket
                        await time.increase(claimFrequency);
            
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        await mainInstance.connect(owner).claim(ONE_ETH, bob.address);

                        const bobTokensAfterClaim = await mainInstance.balanceOf(bob.address);
                        const aliceTokensAfterClaim = await mainInstance.balanceOf(alice.address);

                        expect(bobTokensAfterClaim - bobTokensBefore).to.be.eq(ONE_ETH);
                        expect(aliceTokensAfterClaim - aliceTokensBefore).to.be.eq(ONE_ETH);

                        await mainInstance.connect(bob).transfer(alice.address,ONE_ETH)

                        const bobTokensAfterTransfer = await mainInstance.balanceOf(bob.address);
                        const aliceTokensAfterTransfer = await mainInstance.balanceOf(alice.address);

                        expect(bobTokensAfterTransfer - bobTokensBefore).to.be.eq(0);
                        expect(aliceTokensAfterTransfer - aliceTokensAfterClaim).to.be.eq(ONE_ETH);

                    }); 

                    it("shouldnt exceed holdersMax", async() => {
                        const {
                            owner,
                            alice,
                            bob,
                            charlie,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                        await mainInstance.connect(owner).claim(ethers.parseEther('10'), owner.address);

                        await mainInstance.connect(owner).transfer(bob.address, ethers.parseEther('1'));
                        await mainInstance.connect(owner).transfer(alice.address, ethers.parseEther('1'));

                        await mainInstance.setHoldersMax(1);

                        await expect(
                            mainInstance.connect(owner).transfer(charlie.address, ethers.parseEther('1'))
                        ).to.be.revertedWithCustomError(mainInstance, 'MaxHoldersCountExceeded').withArgs(1);
                        
                    });

                    it("shouldn't _preventPanic when transfer", async() => {
                        // make a test when Bob can send to Alice only 50% of their tokens through a day
                        const {
                            owner,
                            alice,
                            bob,
                            charlie,
                            buyPrice,
                            lockupIntervalAmount,
                            claimFrequency,
                            buySellToken,
                            uniswapRouterInstance,
                            erc20ReservedToken,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                        const InitialSendFunds = ethers.parseEther('1');
                        const bobTokensBefore = await mainInstance.balanceOf(bob.address);
                        const aliceTokensBefore = await mainInstance.balanceOf(alice.address);

                        await mainInstance.connect(owner).claim(InitialSendFunds, bob.address);

                        const bobTokensAfterClaim = await mainInstance.balanceOf(bob.address);
                        const aliceTokensAfterClaim = await mainInstance.balanceOf(alice.address);

                        expect(bobTokensAfterClaim - bobTokensBefore).to.be.eq(InitialSendFunds);
                        expect(aliceTokensAfterClaim - aliceTokensBefore).to.be.eq(0);
                        
                        const DurationForAlice = 24n*60n*60n; // day
                        const RateForAlice = 5000n; // 50%
                        const smthFromOwner= 1n;
                        await mainInstance.connect(owner).setRateLimit([DurationForAlice, RateForAlice])

                        // can't send tokens to new members before owner put him into whitelist(will transfer some tokens to him)
                        await expect(
                            mainInstance.connect(bob).transfer(alice.address, bobTokensAfterClaim)
                        ).to.be.revertedWithCustomError(mainInstance, "OwnerAndManagersOnly");
                        
                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        // send a little
                        await mainInstance.connect(owner).claim(smthFromOwner, alice.address);
                        
                        // now will be ok
                        await mainInstance.connect(bob).transfer(alice.address, bobTokensAfterClaim);

                        const bobTokensAfterTransfer = await mainInstance.balanceOf(bob.address);
                        const aliceTokensAfterTransfer = await mainInstance.balanceOf(alice.address);

                        //expect(bobTokensAfterClaim.mul(RateForAlice).div(FRACTION)).to.be.eq(bobTokensAfterTransfer);
                        //expect(bobTokensAfterClaim.add(smthFromOwner).sub(bobTokensAfterClaim.mul(RateForAlice).div(FRACTION))).to.be.eq(aliceTokensAfterTransfer);
                        expect(bobTokensAfterTransfer).to.be.eq(0);
                        expect(bobTokensAfterClaim + smthFromOwner).to.be.eq(aliceTokensAfterTransfer);
                        
                        // try to send all that left
                        let tx = await mainInstance.connect(bob).transfer(alice.address, bobTokensAfterTransfer);
                        
                        let rc = await tx.wait();
                            
                        // here fast and stupid way to find event PanicSellRateExceeded that cann't decoded if happens in external contract
                        let arr2compare = [
                            ethers.id("PanicSellRateExceeded(address,address,uint256)"), // keccak256
                            '0x'+(bob.address.replace('0x','')).padStart(64, '0'),
                            '0x'+(alice.address.replace('0x','')).padStart(64, '0')
                        ]
                        
                        let event = rc.logs.find(event => JSON.stringify(JSON.stringify(event.topics)).toLowerCase() === JSON.stringify(JSON.stringify(arr2compare)).toLowerCase());
                        let eventExists = (typeof(event) !== 'undefined') ? true : false;

                        expect(eventExists).to.be.eq(false);
                    }); 

                    it("shouldnt locked up tokens if owner claim to himself", async() => {
                        const {
                            owner,
                            alice,
                            bob,
                            charlie,
                            david,
                            buyPrice,
                            lockupIntervalAmount,
                            claimFrequency,
                            buySellToken,
                            uniswapRouterInstance,
                            erc20ReservedToken,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                        const ONE_ETH = ethers.parseEther('1');

                        await mainInstance.connect(owner).claim(ONE_ETH, owner.address);
                        expect(await mainInstance.balanceOf(owner.address)).to.be.eq(ONE_ETH);

                        await mainInstance.connect(owner).transfer(alice.address,ONE_ETH);
                        expect(await mainInstance.balanceOf(alice.address)).to.be.eq(ONE_ETH);

                        const smthFromOwner= 1n;
                        // can't send tokens to new members before owner put him into whitelist(will transfer some tokens to him)
                        await expect(
                            mainInstance.connect(alice).transfer(david.address,ONE_ETH)
                        ).to.be.revertedWithCustomError(mainInstance, "OwnerAndManagersOnly");
                        
                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        // send a little
                        await mainInstance.connect(owner).claim(smthFromOwner, david.address);
                        
                        // now will be ok
                        await mainInstance.connect(alice).transfer(david.address,ONE_ETH);
                        expect(await mainInstance.balanceOf(david.address)).to.be.eq(ONE_ETH + smthFromOwner);
                        
                    }); 

                    it("shouldnt locked up tokens if not exceed max_transfer_count", async() => {
                        
                        const {
                            owner,
                            bob,
                            charlie,
                            buyPrice,
                            lockupIntervalAmount,
                            claimFrequency,
                            buySellToken,
                            uniswapRouterInstance,
                            erc20ReservedToken,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                        const smthFromOwner= 1n;

                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        // send a little
                        await mainInstance.connect(owner).claim(smthFromOwner, charlie.address);

                        await mainInstance.connect(owner).addManager(bob.address);
                        
                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });
                        await mainInstance.connect(bob).claim(ethers.parseEther('1'), bob.address);
                        
                        //await expect(mainInstance.connect(bob).transfer(charlie.address, ethers.parseEther('1'))).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                        await expect(mainInstance.connect(bob).transfer(charlie.address, ethers.parseEther('1'))).not.to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                        
                    }); 

                    it("should locked up tokens", async() => {
                        const {
                            owner,
                            alice,
                            charlie,
                            david,
                            eve,
                            buyPrice,
                            lockupIntervalAmount,
                            claimFrequency,
                            buySellToken,
                            uniswapRouterInstance,
                            erc20ReservedToken,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                        await mainInstance.connect(owner).increaseHoldersThreshold(ethers.parseEther('1'))

                        const smthFromOwner= ethers.parseEther('1');

                        // send a little to Sales contract. Alice will be owner
                        const SaleMockF = await ethers.getContractFactory("SaleMock");
                        const SaleMock = await SaleMockF.connect(alice).deploy();

                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        await mainInstance.connect(owner).claim(smthFromOwner, SaleMock.target);
                        await mainInstance.connect(alice).startSale(SaleMock.target, 10n*86400n);
                        await expect(
                            mainInstance.connect(alice).startSale(SaleMock.target, 10n*86400n)
                        ).to.be.revertedWithCustomError(mainInstance, 'AlreadyCalled');

                        
                        // transfer from SaleContract to David. now David have locked up tokens
                        await SaleMock.connect(alice).transferTokens(mainInstance.target, david.address, smthFromOwner);

                        // exceed maximum transferCount. now transfer revert it tokens locked up
                        await mainInstance.connect(owner).setReceivedTransfersCount(david.address, 10n);
                        await expect(
                            mainInstance.connect(david).transfer(eve.address,ethers.parseEther('0.8'))
                        ).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");

                    }); 

                    it("should locked up tokens when receivedTransfersCount > 4", async() => {
                        const {
                            owner,
                            alice,
                            charlie,
                            david,
                            eve,
                            buyPrice,
                            lockupIntervalAmount,
                            claimFrequency,
                            buySellToken,
                            uniswapRouterInstance,
                            erc20ReservedToken,
                            mainInstance
                        } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                        await mainInstance.connect(owner).increaseHoldersThreshold(ethers.parseEther('1'))

                        const smthFromOwner= ethers.parseEther('1');

                        // send a little to Sales contract. Alice will be owner
                        const SaleMockF = await ethers.getContractFactory("SaleMock");
                        const SaleMock = await SaleMockF.connect(alice).deploy();

                        // pass time to clear bucket
                        await time.increase(claimFrequency);
                        await addNewHolderAndSwap({
                            owner: owner,
                            account: charlie,
                            buyPrice: buyPrice,
                            lockupIntervalAmount: lockupIntervalAmount,
                            mainInstance: mainInstance,
                            buySellToken: buySellToken,
                            uniswapRouterInstance: uniswapRouterInstance,
                            erc20ReservedToken: erc20ReservedToken
                        });

                        await mainInstance.connect(owner).claim(smthFromOwner, SaleMock.target);
                        await mainInstance.connect(alice).startSale(SaleMock.target, 10n*86400n);

                        // transfer from SaleContract to David. now David have locked up tokens
                        await SaleMock.connect(alice).transferTokens(mainInstance.target, david.address, smthFromOwner);

                        // so boths, David and Eve are common users

                        // start to calculate transfersCount
                        expect(await mainInstance.receivedTransfersCount(david.address)).to.be.eq(0);
                        expect(await mainInstance.receivedTransfersCount(eve.address)).to.be.eq(0);

                        // transfer to charlie and back to david 
                        await mainInstance.connect(david).transfer(eve.address,ethers.parseEther('1'));
                        await mainInstance.connect(eve).transfer(david.address,ethers.parseEther('1'));
                        expect(await mainInstance.receivedTransfersCount(david.address)).to.be.eq(1n);
                        expect(await mainInstance.receivedTransfersCount(eve.address)).to.be.eq(1n);

                        // again
                        await mainInstance.connect(david).transfer(eve.address,ethers.parseEther('1'));
                        await mainInstance.connect(eve).transfer(david.address,ethers.parseEther('1'));
                        expect(await mainInstance.receivedTransfersCount(david.address)).to.be.eq(2n);
                        expect(await mainInstance.receivedTransfersCount(eve.address)).to.be.eq(2n);

                        // and again
                        await mainInstance.connect(david).transfer(eve.address,ethers.parseEther('1'));
                        await mainInstance.connect(eve).transfer(david.address,ethers.parseEther('1'));
                        expect(await mainInstance.receivedTransfersCount(david.address)).to.be.eq(3n);
                        expect(await mainInstance.receivedTransfersCount(eve.address)).to.be.eq(3n);

                        // the last one, but eve send only half of it
                        await mainInstance.connect(david).transfer(eve.address,ethers.parseEther('1'));
                        await mainInstance.connect(eve).transfer(david.address,ethers.parseEther('0.5'));
                        expect(await mainInstance.receivedTransfersCount(david.address)).to.be.eq(4n);
                        expect(await mainInstance.receivedTransfersCount(eve.address)).to.be.eq(4n);

                        // david should have receivedTransfersCount => 4. after that tokens(which keep save gradual lock-up), can't be transferred until lock-up passed
                        await expect(mainInstance.connect(david).transfer(eve.address,ethers.parseEther('0.5'))).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                        // eve have receivedTransfersCount => 4 too. 
                        await expect(mainInstance.connect(eve).transfer(david.address,ethers.parseEther('0.5'))).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                        // even if eve will become as a manager. Tokens have already locked up
                        await mainInstance.connect(owner).addManager(eve.address);
                        await expect(mainInstance.connect(eve).transfer(david.address,ethers.parseEther('0.5'))).to.be.revertedWithCustomError(mainInstance, "InsufficientAmount");
                        
                    }); 

                }); 

            });

        });

        describe("uniswap settings", function () {

            it("shouldnt swap if owner send the tokens before", async() => {
                const {
                    owner,
                    bob,
                    lockupIntervalAmount,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettings);

                let ts, timeUntil;
            
                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                
                await expect(uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                )).to.be.revertedWith('UniswapV2: TRANSFER_FAILED'); // reverted in TradedToken with "OwnerAndManagersOnly"
                //Pancake: TRANSFER_FAILED
            });
   
            xit("synth case: try to get stored average price", async() => {
                const {
                    owner,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                maxliquidity = tradedReserve2 - tradedReserve1;

                add2Liquidity = maxliquidity / 1000n;

                await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                await time.increase(5);
                await mainInstance.connect(owner).addLiquidity(add2Liquidity);

            });

            it("should add liquidity. liquidity contract middleware shouldn't have funds left after added liquidity", async() => {
                const {
                    owner,
                    erc20ReservedToken,
                    internalLiquidityAddress,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                maxliquidity = tradedReserve2 - tradedReserve1;

                add2Liquidity = maxliquidity / 1000n;

                // math presicion!!!  left can be like values less then 10
                expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
                expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
                // adding liquidity
                await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                // shouldn't have any tokens left on middleware
                expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
                expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
                // and again
                await mainInstance.connect(owner).addLiquidity(add2Liquidity);
                expect(await mainInstance.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
                expect(await erc20ReservedToken.balanceOf(internalLiquidityAddress)).to.be.lt(10n);
            });

            it("should _preventPanic", async() => {
                const {
                    owner,
                    charlie,
                    lockupIntervalAmount,
                    erc20ReservedToken,
                    uniswapRouterInstance,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                const uniswapV2Pair = await mainInstance.uniswapV2Pair();

                const DurationForUniswap = 24n*60n*60n; // day
                const RateForUniswap = 5000n; // 50%
                await mainInstance.connect(owner).setRateLimit([DurationForUniswap, RateForUniswap])

                //await mainInstance.connect(owner).claim(ethers.parseEther('1'), charlie.address);
                await mainInstance.connect(owner).claim(ethers.parseEther('0.5'), charlie.address);

                await mainInstance.connect(charlie).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                let ts = await time.latest();
                let timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                //swapExactTokensForTokensSupportingFeeOnTransferTokens
                //swapExactTokensForTokens
                await uniswapRouterInstance.connect(charlie).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                    charlie.address, //address to,
                    timeUntil //uint deadline   

                );

                await mainInstance.connect(owner).claim(ethers.parseEther('0.5'), charlie.address);
                // // try to send another part
                await mainInstance.connect(charlie).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));

                //PanicSellRateExceeded()
                let charlieBalanceBeforePanic = await mainInstance.balanceOf(charlie.address);
                let charlieBalanceReservedBeforePanic = await erc20ReservedToken.balanceOf(charlie.address);
                let tx = await uniswapRouterInstance.connect(charlie).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        ethers.parseEther('0.5'), //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        charlie.address, //address to,
                        timeUntil //uint deadline   

                );
                let charlieBalanceAfterPanic = await mainInstance.balanceOf(charlie.address);
                let charlieBalanceReservedAfterPanic = await erc20ReservedToken.balanceOf(charlie.address);
                let rc = await tx.wait(); // 0ms, as tx is already confirmed
                // let event = rc.events.find(event => event.event === 'PanicSellRateExceeded');

                // here fast and stupid way to find event PanicSellRateExceeded that cann't decoded if happens in external contract
                let arr2compare = [
                    ethers.id("PanicSellRateExceeded(address,address,uint256)"), // keccak256
                    '0x'+(charlie.address.replace('0x','')).padStart(64, '0'),
                    '0x'+(uniswapV2Pair.replace('0x','')).padStart(64, '0')
                ]
                let event = rc.logs.find(event => JSON.stringify(JSON.stringify(event.topics)).toLowerCase() === JSON.stringify(JSON.stringify(arr2compare)).toLowerCase());
                let eventExists = (typeof(event) !== 'undefined') ? true : false;
                expect(eventExists).to.be.eq(true);
                if (eventExists) {
                    // address: '0x2d13826359803522cCe7a4Cfa2c1b582303DD0B4',
                    // topics: [
                    //     '0xda8c6cfc61f9766da27a11e69038df366444016f44f525a2907f393407bfc6c3',
                    //     '0x00000000000000000000000090f79bf6eb2c4f870365e785982e1f101e93b906',
                    //     '0x0000000000000000000000009b7889734ac75060202410362212d365e9ee1ef5'
                    // ],
                    expect(event.address).to.be.eq(mainInstance.target);
                    expect(ethers.getAddress( event.topics[1].replace('000000000000000000000000','') )).to.be.eq(charlie.address);
                    expect(ethers.getAddress( event.topics[2].replace('000000000000000000000000','') )).to.be.eq(uniswapV2Pair);

                    // we will adjust value in panic situation from amount to 5
                    // so transaction didn't revert but emitted event "PanicSellRateExceeded"

                    expect(charlieBalanceBeforePanic - 5n).to.be.eq(charlieBalanceAfterPanic);
                    expect(charlieBalanceReservedBeforePanic + 5n).to.be.eq(charlieBalanceReservedAfterPanic);
                }
                //----------------------
            
            }); 

            it("shouldnt add liquidity", async() => {
                const {
                    owner,
                    internalLiquidity,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                let tradedReserve1,tradedReserve2,priceAv, maxliquidity, add2Liquidity;
                [tradedReserve1, tradedReserve2, priceAv] = await mainInstance.connect(owner).maxAddLiquidity();

                maxliquidity = tradedReserve2 - tradedReserve1;
                add2Liquidity = maxliquidity;//.abs()//.mul(1).div(10000);

                await expect(mainInstance.connect(owner).addLiquidity(add2Liquidity)).to.be.revertedWithCustomError(internalLiquidity, "PriceDropTooBig");

                // or try to max from maxAddLiquidity
                // seems we can add ZERO. Contract will try to use max as possible
                //await expect(mainInstance.connect(owner).addLiquidity(0)).to.be.revertedWith("CanNotBeZero");

                

            });

            describe("taxes", function () {
                it("should setup buyTaxMax and sellTaxMax when deploy", async() => {
                    const {
                        maxBuyTax,
                        maxSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    expect(await mainInstance.buyTaxMax()).to.be.equal(maxBuyTax);
                    expect(await mainInstance.sellTaxMax()).to.be.equal(maxSellTax);
                }); 

                it("should sellTax and buyTax to be zero when deploy", async() => {
                    const {
                        storedBuyTax,
                        storedSellTax
                    } = await loadFixture(deployAndTestUniswapSettings);
                    expect(storedBuyTax).to.be.equal(0);
                    expect(storedSellTax).to.be.equal(0);
                }); 

                it("shouldt setup buyTax value more then buyTaxMax", async() => {
                    const {
                        maxBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    await expect(mainInstance.setTaxes(maxBuyTax + 1n, storedSellTax)).to.be.revertedWithCustomError(mainInstance, `TaxesTooHigh`);
                }); 

                it("shouldt setup sellTax value more then sellTaxMax", async() => {
                    const {
                        maxSellTax,
                        storedBuyTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    await expect(mainInstance.setTaxes(storedBuyTax, maxSellTax + 1n)).to.be.revertedWithCustomError(mainInstance, `TaxesTooHigh`);
                }); 
                
                it("should setup sellTax", async() => {
                    const {
                        maxSellTax,
                        storedBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    const oldValue = storedSellTax;

                    const value = maxSellTax - 1n;
                    await mainInstance.setTaxes(storedBuyTax, value);

                    const newValue = await mainInstance.sellTax();
                    
                    expect(oldValue).not.to.be.eq(newValue);
                    expect(value).to.be.eq(newValue);
                }); 

                it("should setup buyTax", async() => {
                    const {
                        maxBuyTax,
                        storedBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    const oldValue = storedBuyTax;

                    const value = maxBuyTax - 1n;
                    await mainInstance.setTaxes(value, storedSellTax);

                    const newValue = await mainInstance.buyTax();

                    expect(oldValue).not.to.be.eq(newValue);
                    expect(value).to.be.eq(newValue);
                }); 

                it("should setup sellTax gradually", async() => {
                    const {
                        maxSellTax,
                        storedBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    await mainInstance.setTaxesInfoInitWithoutTaxes([storedBuyTax, storedSellTax, 1000n, 1000n, true, true]);
                    const oldValue = await mainInstance.sellTax();

                    const value = maxSellTax - 1n;
                    await mainInstance.setTaxes(storedBuyTax, value);

                    const newValueStart = await mainInstance.sellTax();
                    
                    await time.increase(500);

                    const newValueHalf = await mainInstance.sellTax();

                    await time.increase(10000);

                    const newValueOverFinal = await mainInstance.sellTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.lt(newValueHalf);
                    expect(newValueHalf).to.be.lt(newValueOverFinal);
                    expect(value).to.be.eq(newValueOverFinal);

                }); 

                it("should setup buyTax gradually", async() => {
                    const {
                        maxBuyTax,
                        storedBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    await mainInstance.setTaxesInfoInitWithoutTaxes([storedBuyTax, storedSellTax, 1000n, 1000n, true, true]);
                    const oldValue = await mainInstance.buyTax();

                    const value = maxBuyTax - 1n;
                    await mainInstance.setTaxes(value, storedSellTax);

                    const newValueStart = await mainInstance.buyTax();

                    await time.increase(500);

                    const newValueHalf = await mainInstance.buyTax();

                    await time.increase(10000);

                    const newValueOverFinal = await mainInstance.buyTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.lt(newValueHalf);
                    expect(newValueHalf).to.be.lt(newValueOverFinal);
                    expect(value).to.be.eq(newValueOverFinal);

                }); 

                it("should setup buyTax gradually down", async() => {
                    const {
                        maxBuyTax,
                        storedBuyTax,
                        storedSellTax,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettings);

                    const value = maxBuyTax - 1n;

                    await mainInstance.setTaxes(value, storedSellTax);
                    const oldValue = await mainInstance.buyTax();

                    await mainInstance.setTaxesInfoInitWithoutTaxes([storedBuyTax, storedSellTax, 1000n, 1000n, true, true]);
                    // to make setup fromTax as `maxBuyTax.sub(ONE)` need to pass full time duration. 
                    // if call setTax in the middle of period then contract will calculate taxFrom as (from+to)/2
                    await time.increase(10000);
                    //----------------------------------

                    const value2 = 1n;

                    await mainInstance.setTaxes(value2, storedSellTax);

                    const newValueStart = await mainInstance.buyTax();

                    await time.increase(500);

                    const newValueHalf = await mainInstance.buyTax();

                    await time.increase(10000);

                    const newValueOverFinal = await mainInstance.buyTax();
                    
                    expect(oldValue).to.be.eq(newValueStart);
                    expect(newValueStart).to.be.gt(newValueHalf);
                    expect(newValueHalf).to.be.gt(newValueOverFinal);
                    expect(value2).to.be.eq(newValueOverFinal);

                }); 

                it("should burn buyTax", async() => {
                    const {
                        owner,
                        bob,
                        charlie,
                        buyPrice,
                        storedSellTax,
                        lockupIntervalAmount,
                        claimFrequency,
                        buySellToken,
                        uniswapRouterInstance,
                        erc20ReservedToken,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                    // pass time to clear bucket
                    await time.increase(claimFrequency);
                    await addNewHolderAndSwap({
                        owner: owner,
                        account: charlie,
                        buyPrice: buyPrice,
                        lockupIntervalAmount: lockupIntervalAmount,
                        mainInstance: mainInstance,
                        buySellToken: buySellToken,
                        uniswapRouterInstance: uniswapRouterInstance,
                        erc20ReservedToken: erc20ReservedToken
                    });
                
                    let ts, timeUntil;

                    // make snapshot
                    // make swapExactTokensForTokens  without tax
                    // got amount that user obtain
                    // restore snapshot
                    // setup buy tax and the same swapExactTokensForTokens as previous
                    // obtained amount should be less by buytax
                    //---------------------------
                    //const snapObj = await snapshot();
                    // reverted with: 
                    //   Error: CONNECTION ERROR: Couldn't connect to node http://localhost:8545.
                    let snapId = await ethers.provider.send('evm_snapshot', []);

                    await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                    ts = await time.latest();
                    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                    let bobBalanceBeforeWoTax = await mainInstance.balanceOf(bob.address);
                    const smthFromOwner = 1;
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ethers.parseEther('0.5'), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    
                    let bobBalanceAfterWoTax = await mainInstance.balanceOf(bob.address);

                    //await snapObj.restore();
                    await ethers.provider.send('evm_revert', [snapId]);
                    //----

                    const tax = FRACTION * 10n / 100n;
                    
                    await mainInstance.setTaxes(tax, storedSellTax);

                    await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                    ts = await time.latest();
                    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                    let bobBalanceBeforeWithTax = await mainInstance.balanceOf(bob.address);
                    
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ethers.parseEther('0.5'), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWithTax = await mainInstance.balanceOf(bob.address);
                    //-----

                    // now check
                    let deltaWithTax = bobBalanceAfterWithTax - bobBalanceBeforeWithTax;
                    let deltaWWoTax = bobBalanceAfterWoTax - bobBalanceBeforeWoTax;

                    expect(deltaWithTax).not.be.eq(deltaWWoTax);
                    expect(deltaWithTax).not.be.eq(deltaWWoTax * tax / FRACTION);

                });

                it("should burn sellTax", async() => {
                  
                    const {
                        owner,
                        bob,
                        charlie,
                        buyPrice,
                        storedBuyTax,
                        lockupIntervalAmount,
                        claimFrequency,
                        buySellToken,
                        uniswapRouterInstance,
                        erc20ReservedToken,
                        mainInstance
                    } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwapAndWhitelisted);

                    // pass time to clear bucket
                    await time.increase(claimFrequency);
                    await addNewHolderAndSwap({
                        owner: owner,
                        account: charlie,
                        buyPrice: buyPrice,
                        lockupIntervalAmount: lockupIntervalAmount,
                        mainInstance: mainInstance,
                        buySellToken: buySellToken,
                        uniswapRouterInstance: uniswapRouterInstance,
                        erc20ReservedToken: erc20ReservedToken
                    });

                    let ts, timeUntil;
                   
                    // make swapExactTokensForTokens  without tax to obtain tradedToken
                    // make snapshot
                    // make swapExactTokensForTokens  without tax
                    // got amount that user obtain
                    // restore snapshot
                    // setup buy tax and the same swapExactTokensForTokens as previous
                    // obtained amount should be less by buytax
                    //---------------------------
                    await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                    await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                    ts = await time.latest();
                    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                    let tmp = await mainInstance.balanceOf(bob.address);
                    const smthFromOwner = 1;
                    await mainInstance.connect(owner).claim(smthFromOwner, bob.address);

                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        ethers.parseEther('0.5'), //uint amountIn,
                        0, //uint amountOutMin,
                        [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );

                    let tmp2 = await mainInstance.balanceOf(bob.address);
                    //const obtainERC777Tokens = tmp2 - tmp;
                    //make a little bit less that obtainERC777Tokens. because when try to swap. it will stuck in div precision
                    const obtainERC777Tokens = tmp2 - tmp - 10n;
                    //----
                    // const snapObj = await snapshot();
                    // reverted with: 
                    //   Error: CONNECTION ERROR: Couldn't connect to node http://localhost:8545.
                    let snapId = await ethers.provider.send('evm_snapshot', []);

                    ts = await time.latest();
                    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                    let bobBalanceBeforeWoTax = await erc20ReservedToken.balanceOf(bob.address);

                    await mainInstance.connect(bob).approve(uniswapRouterInstance.target, obtainERC777Tokens);
                    //await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
                    
                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        obtainERC777Tokens, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWoTax = await erc20ReservedToken.balanceOf(bob.address);

                    //await snapObj.restore();
                    await ethers.provider.send('evm_revert', [snapId]);
                    //----

                    const tax = FRACTION * 10n / 100n;
                    
                    await mainInstance.setTaxes(storedBuyTax, tax);

                    ts = await time.latest();
                    timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                    let bobBalanceBeforeWithTax = await erc20ReservedToken.balanceOf(bob.address);

                    await mainInstance.connect(bob).approve(uniswapRouterInstance.target, obtainERC777Tokens);
                    //await mainInstance.connect(owner).claim(smthFromOwner, bob.address);
                    await uniswapRouterInstance.connect(bob).swapExactTokensForTokensSupportingFeeOnTransferTokens(
                        obtainERC777Tokens, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   

                    );
                    let bobBalanceAfterWithTax = await erc20ReservedToken.balanceOf(bob.address);
                    //-----

                    // now check
                    let deltaWithTax = bobBalanceAfterWithTax - bobBalanceBeforeWithTax;
                    let deltaWWoTax = bobBalanceAfterWoTax - bobBalanceBeforeWoTax;

                    expect(deltaWithTax).not.be.eq(deltaWWoTax);
                    expect(deltaWithTax).not.be.eq(deltaWWoTax * tax / FRACTION);

                });
            }); 

        });

        describe("whitelist", function () {
            it("new governor should setup only owner or current governor", async() => {
                const {
                    owner,
                    alice,
                    bob,
                    charlie,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                await expect( 
                    mainInstance.connect(alice).setGovernor(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'OwnerOrGovernorOnly');

                await mainInstance.connect(owner).setGovernor(alice.address);

                await expect( 
                    mainInstance.connect(charlie).setGovernor(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'OwnerOrGovernorOnly');

                await mainInstance.connect(alice).setGovernor(bob.address);

                await expect( 
                    mainInstance.connect(alice).setGovernor(alice.address)
                ).to.be.revertedWithCustomError(mainInstance, 'OwnerOrGovernorOnly');

            });

            it("only governor can manage communities/exchanges/sources list", async() => {

                const {
                    owner,
                    alice,
                    bob,
                    charlie,
                    timeUntil,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                await mainInstance.connect(owner).setGovernor(alice.address);

                //not owner
                await expect( 
                    mainInstance.connect(owner).communitiesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(owner).communitiesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(owner).exchangesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(owner).exchangesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(owner).sourcesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(owner).sourcesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');

                // not any users
                await expect( 
                    mainInstance.connect(charlie).communitiesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(charlie).communitiesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(charlie).exchangesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(charlie).exchangesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(charlie).sourcesAdd(bob.address, timeUntil)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');
                await expect( 
                    mainInstance.connect(charlie).sourcesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'GovernorOnly');

                // only current governor
                expect(await mainInstance.communities(bob.address)).to.be.eq(0n);
                expect(await mainInstance.exchanges(bob.address)).to.be.eq(0n);
                expect(await mainInstance.sources(bob.address)).to.be.eq(0n);

                // but timeUntil can not be zero
                await expect( 
                    mainInstance.connect(alice).communitiesAdd(bob.address, 0n)
                ).to.be.revertedWithCustomError(mainInstance, 'CantBeZero');
                await expect( 
                    mainInstance.connect(alice).exchangesAdd(bob.address, 0n)
                ).to.be.revertedWithCustomError(mainInstance, 'CantBeZero');
                await expect( 
                    mainInstance.connect(alice).sourcesAdd(bob.address, 0n)
                ).to.be.revertedWithCustomError(mainInstance, 'CantBeZero');

                await mainInstance.connect(alice).communitiesAdd(bob.address, timeUntil);
                await mainInstance.connect(alice).exchangesAdd(bob.address, timeUntil);
                await mainInstance.connect(alice).sourcesAdd(bob.address, timeUntil);

                expect(await mainInstance.communities(bob.address)).not.to.be.eq(0n);
                expect(await mainInstance.exchanges(bob.address)).not.to.be.eq(0n);
                expect(await mainInstance.sources(bob.address)).not.to.be.eq(0n);

                // governor can remove but until `timeUntil` time passed
                await expect( 
                    mainInstance.connect(alice).communitiesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'CantRemove').withArgs(timeUntil);
                await expect( 
                    mainInstance.connect(alice).exchangesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'CantRemove').withArgs(timeUntil);
                await expect( 
                    mainInstance.connect(alice).sourcesRemove(bob.address)
                ).to.be.revertedWithCustomError(mainInstance, 'CantRemove').withArgs(timeUntil);

                await time.increaseTo(timeUntil+50n);

                //still in list
                expect(await mainInstance.communities(bob.address)).not.to.be.eq(0n);
                expect(await mainInstance.exchanges(bob.address)).not.to.be.eq(0n);
                expect(await mainInstance.sources(bob.address)).not.to.be.eq(0n);
                //but now possible to remove
                await mainInstance.connect(alice).communitiesRemove(bob.address);
                expect(await mainInstance.communities(bob.address)).to.be.eq(0n);
                await mainInstance.connect(alice).exchangesRemove(bob.address);
                expect(await mainInstance.exchanges(bob.address)).to.be.eq(0n);
                await mainInstance.connect(alice).sourcesRemove(bob.address);
                expect(await mainInstance.sources(bob.address)).to.be.eq(0n);
                
            });
            it("shouldnt sell tokens if seller outside whitelist", async() => {
                  
                const {
                    owner,
                    bob,
                    charlie,
                    buyPrice,
                    lockupIntervalAmount,
                    claimFrequency,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;
                
                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                let bobTradeTokeBalanceBefore = await mainInstance.balanceOf(bob.address);
                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                let bobTradeTokeBalanceAfter = await mainInstance.balanceOf(bob.address);
                const tradedTokensToSwapBack = bobTradeTokeBalanceAfter - bobTradeTokeBalanceBefore;
                //let balanceTradedTokens = await mainInstance.balanceOf(bob.address);

                await mainInstance.connect(bob).approve(uniswapRouterInstance.target, tradedTokensToSwapBack);

                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                await expect(
                    uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        tradedTokensToSwapBack, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   
                    )
                ).to.be.revertedWith('TransferHelper: TRANSFER_FROM_FAILED');

                //after adding bob into the communities list tx will pass
                await mainInstance.connect(owner).setGovernor(owner.address);
                await mainInstance.connect(owner).communitiesAdd(bob.address, timeUntil);

                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    tradedTokensToSwapBack, //uint amountIn,
                    0, //uint amountOutMin,
                    [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   
                )

            }); 

            it("shouldn't send back to exchange if durationSendBack are passed", async() => {
                const {
                    owner,
                    bob,
                    charlie,
                    buyPrice,
                    lockupIntervalAmount,
                    claimFrequency,
                    durationSendBack,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;

                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                let bobBalanceTradedTokensBeforeSwap = await mainInstance.balanceOf(bob.address);
                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                let bobBalanceTradedTokensAfterSwap = await mainInstance.balanceOf(bob.address);
                //calculate how much Bob can send back 
                const availableFundToSendBack = bobBalanceTradedTokensAfterSwap - bobBalanceTradedTokensBeforeSwap;
                
                // pass durationSendBack time
                await time.increase(durationSendBack);

                await mainInstance.connect(bob).approve(uniswapRouterInstance.target, availableFundToSendBack);

                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                

                //after adding bob into the communities list tx will pass
                await mainInstance.connect(owner).setGovernor(owner.address);
                await mainInstance.connect(owner).communitiesAdd(bob.address, timeUntil);

                await expect(
                    uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        availableFundToSendBack, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   
                    )
                ).to.be.revertedWith('TransferHelper: TRANSFER_FROM_FAILED');

            }); 

            it("should send back to exchange if durationSendBack are NOT passed", async() => {
                const {
                    owner,
                    bob,
                    charlie,
                    buyPrice,
                    lockupIntervalAmount,
                    claimFrequency,
                    durationSendBack,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;

                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                let bobBalanceTradedTokensBeforeSwap = await mainInstance.balanceOf(bob.address);
                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                let bobBalanceTradedTokensAfterSwap = await mainInstance.balanceOf(bob.address);
                //calculate how much Bob can send back 
                const availableFundToSendBack = bobBalanceTradedTokensAfterSwap - bobBalanceTradedTokensBeforeSwap;

                // // pass durationSendBack time
                // await time.increase(durationSendBack);

                await mainInstance.connect(bob).approve(uniswapRouterInstance.target, availableFundToSendBack);

                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                

                //after adding bob into the communities list tx will pass
                await mainInstance.connect(owner).setGovernor(owner.address);
                await mainInstance.connect(owner).communitiesAdd(bob.address, timeUntil);

                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    availableFundToSendBack, //uint amountIn,
                    0, //uint amountOutMin,
                    [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   
                );

            }); 
            
            it("shouldnt send back to exchange more than was sent to exchange", async() => {
                const {
                    owner,
                    bob,
                    charlie,
                    buyPrice,
                    lockupIntervalAmount,
                    claimFrequency,
                    durationSendBack,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;

                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                let bobBalanceTradedTokensBeforeSwap = await mainInstance.balanceOf(bob.address);
                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                let bobBalanceTradedTokensAfterSwap = await mainInstance.balanceOf(bob.address);
                //calculate how much Bob can send back 
                const availableFundToSendBack = bobBalanceTradedTokensAfterSwap - bobBalanceTradedTokensBeforeSwap;
                expect(availableFundToSendBack).to.be.gt(0n);
                
                const littleBitMoreThanAvailable = availableFundToSendBack+2n;
                // // pass durationSendBack time
                // await time.increase(durationSendBack);

                await mainInstance.connect(bob).approve(uniswapRouterInstance.target, littleBitMoreThanAvailable);

                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                

                //after adding bob into the communities list tx will pass
                await mainInstance.connect(owner).setGovernor(owner.address);
                await mainInstance.connect(owner).communitiesAdd(bob.address, timeUntil);
                
                await expect(
                    uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                        littleBitMoreThanAvailable, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        bob.address, //address to,
                        timeUntil //uint deadline   
                    )
                ).to.be.revertedWith('TransferHelper: TRANSFER_FROM_FAILED');

            }); 

            it("should sell tokens if seller outside whitelist, BUT got them from sources", async() => {
                const {
                    owner,
                    bob,
                    charlie,
                    david,
                    buyPrice,
                    lockupIntervalAmount,
                    claimFrequency,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;
                
                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                let bobTradedTokensBalanceBefore = await mainInstance.balanceOf(bob.address);
                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
                let bobTradedTokensBalanceAfter = await mainInstance.balanceOf(bob.address);
                const tokensToSwap = bobTradedTokensBalanceAfter - bobTradedTokensBalanceBefore;

                //let balanceTradedTokens = await mainInstance.balanceOf(bob.address);
                const halfOfTokensToSwap = tokensToSwap/2n;

                await mainInstance.connect(owner).setGovernor(owner.address);
                // imitation case when SalesContract transfer tokens to David. and hardcoded holderMax before it
                await mainInstance.connect(owner).setHoldersMax(0);

                // transfer to david half before bob become in sources list
                await mainInstance.connect(owner).addManager(bob.address);
                await mainInstance.connect(bob).transfer(david.address, halfOfTokensToSwap);
                await mainInstance.connect(owner).removeManagers([bob.address]);

                // put Bob into the sources list
                // it's just imitation of SalesContract
                
                await mainInstance.connect(owner).sourcesAdd(bob.address, timeUntil);

                // and transfer to david half after bob become in sources list
                await mainInstance.connect(bob).transfer(david.address, halfOfTokensToSwap);

                expect(await mainInstance.balanceOf(david.address)).to.be.eq(tokensToSwap);

                // now try to sell only a half
                await mainInstance.connect(david).approve(uniswapRouterInstance.target, halfOfTokensToSwap);

                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;
                await expect(
                    uniswapRouterInstance.connect(david).swapExactTokensForTokens(
                        halfOfTokensToSwap, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        david.address, //address to,
                        timeUntil //uint deadline   
                    )
                ).not.to.be.revertedWith('TransferHelper: TRANSFER_FROM_FAILED');

                // but second half will reverted
                await mainInstance.connect(david).approve(uniswapRouterInstance.target, halfOfTokensToSwap);
                await expect(
                    uniswapRouterInstance.connect(david).swapExactTokensForTokens(
                        halfOfTokensToSwap, //uint amountIn,
                        0, //uint amountOutMin,
                        [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                        david.address, //address to,
                        timeUntil //uint deadline   
                    )
                ).to.be.revertedWith('TransferHelper: TRANSFER_FROM_FAILED');

                // //after adding bob into the communities list tx will pass
                // await mainInstance.connect(owner).setGovernor(owner.address);
                // await mainInstance.connect(owner).communitiesAdd(bob.address);

                // await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                //     balanceTradedTokens, //uint amountIn,
                //     0, //uint amountOutMin,
                //     [mainInstance.target, erc20ReservedToken.target], //address[] calldata path,
                //     bob.address, //address to,
                //     timeUntil //uint deadline   
                // )

            }); 

            it("should buy tokens if seller outside whitelist", async() => {
                  
                const {
                    owner,
                    bob,
                    charlie,
                    buyPrice,
                    storedBuyTax,
                    lockupIntervalAmount,
                    claimFrequency,
                    buySellToken,
                    uniswapRouterInstance,
                    erc20ReservedToken,
                    mainInstance
                } = await loadFixture(deployAndTestUniswapSettingsWithFirstSwap);

                // pass time to clear bucket
                await time.increase(claimFrequency);
                await addNewHolderAndSwap({
                    owner: owner,
                    account: charlie,
                    buyPrice: buyPrice,
                    lockupIntervalAmount: lockupIntervalAmount,
                    mainInstance: mainInstance,
                    buySellToken: buySellToken,
                    uniswapRouterInstance: uniswapRouterInstance,
                    erc20ReservedToken: erc20ReservedToken
                });

                let ts, timeUntil;
                
                // make swapExactTokensForTokens  without tax to obtain tradedToken
                // make snapshot
                // make swapExactTokensForTokens  without tax
                // got amount that user obtain
                // restore snapshot
                // setup buy tax and the same swapExactTokensForTokens as previous
                // obtained amount should be less by buytax
                //---------------------------
                await erc20ReservedToken.connect(owner).mint(bob.address, ethers.parseEther('0.5'));
                await erc20ReservedToken.connect(bob).approve(uniswapRouterInstance.target, ethers.parseEther('0.5'));
                ts = await time.latest();
                timeUntil = BigInt(ts) + lockupIntervalAmount*24n*60n*60n;

                await uniswapRouterInstance.connect(bob).swapExactTokensForTokens(
                    ethers.parseEther('0.5'), //uint amountIn,
                    0, //uint amountOutMin,
                    [erc20ReservedToken.target, mainInstance.target], //address[] calldata path,
                    bob.address, //address to,
                    timeUntil //uint deadline   

                );
            }); 
        }); 
    });
    
});