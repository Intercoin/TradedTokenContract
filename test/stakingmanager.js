
const { expect } = require('chai');
const hre = require("hardhat");
const { time, loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
require("@nomicfoundation/hardhat-chai-matchers");
const { deployStakingManager } = require("./fixtures/deploy.js");

describe("StakingManager", function () {
    
    async function getBalances(res, acc) {
        const {
            StakeManager,
            TradedTokenImitation,
            SimpleERC20
        } = res;

        return {
            shares: await StakeManager.connect(acc).sharesByStaker(acc.address),
            traded: await TradedTokenImitation.connect(acc).balanceOf(acc.address),
            staked: await SimpleERC20.connect(acc).balanceOf(acc.address)
        }
    }
    describe("availableToClaim tests", function () {
        describe("without bonuses", function () {
            it("should stake", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    defaultStakeDuration,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;
                
                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = defaultStakeDuration;
                await SimpleERC20.mint(alice, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                const aliceBalancesBefore = await getBalances(res, alice);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                const aliceBalancesAfter = await getBalances(res, alice);

                expect(aliceBalancesBefore.shares).to.eq(0n);
                expect(aliceBalancesAfter.shares).to.eq(amountToStake);

                expect(aliceBalancesBefore.staked).to.eq(amountToStake);
                expect(aliceBalancesAfter.staked).to.eq(0n);
            });

            it("should unstake", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    defaultStakeDuration,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;
                
                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = defaultStakeDuration;
                await SimpleERC20.mint(alice, amountToStake);

                //await TradedTokenImitation.setAvailableToClaim(0n);
                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                //await TradedTokenImitation.setAvailableToClaim(0n);
                //await TradedTokenImitation.setAvailableToClaim(amountToStake);
                const aliceBalancesBefore = await getBalances(res, alice);
                
                await StakeManager.connect(alice).unstake();

                const aliceBalancesAfter = await getBalances(res, alice);

                expect(aliceBalancesBefore.shares).to.eq(amountToStake);
                expect(aliceBalancesAfter.shares).to.eq(0n);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(availableToClaim);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(amountToStake);
                
            });

            it("should claim(only rewards)", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    defaultStakeDuration,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;
                
                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = defaultStakeDuration;
                await SimpleERC20.mint(alice, amountToStake);

                //await TradedTokenImitation.setAvailableToClaim(0n);
                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                //await TradedTokenImitation.setAvailableToClaim(0n);
                //await TradedTokenImitation.setAvailableToClaim(amountToStake);
                const aliceBalancesBefore = await getBalances(res, alice);
                
                await StakeManager.connect(alice).claim();

                const aliceBalancesAfter = await getBalances(res, alice);

                expect(aliceBalancesBefore.shares).to.eq(amountToStake);
                expect(aliceBalancesAfter.shares).to.eq(amountToStake);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(availableToClaim);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(0n);
            });
        });

        describe("with bonusRate = x3", function () {
            const getShares = function(data) {
                //return FRACTION + (subAndGetNoneZero(duration, defaultStakeDuration) / defaultStakeDuration * defaultStakeDuration) * bonusSharesRate;
                const _multiplier = data.FRACTION + (((data.duration - data.defaultStakeDuration) / data.defaultStakeDuration) * data.defaultStakeDuration) * data.bonusSharesRate;    
                return data.amount * _multiplier / data.FRACTION;
            }
            
            async function deployStakingManagerWithBonus(bonusMultiplier) {
                const res = await loadFixture(deployStakingManager);

                const {
                    alice,
                    bonusSharesRate,
                    StakeManager,
                } = res;
                const bonusSharesRateIncreased = bonusSharesRate * bonusMultiplier;
                await StakeManager.connect(alice).setBonusSharesRate(bonusSharesRateIncreased);

                //return res;
                return {...res, ...{
                    bonusSharesRateIncreased
                }};
            }

            it("should unstake", async() => {
                const bonusMultiplier = 3n;
                const res = await deployStakingManagerWithBonus(bonusMultiplier);
                
                const {
                    alice,
                    defaultStakeDuration,
                    bonusSharesRateIncreased,
                    FRACTION,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = defaultStakeDuration*2n;
                await SimpleERC20.mint(alice, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                const aliceBalancesBefore = await getBalances(res, alice);

                const expectedShares = await StakeManager.connect(alice).calculateRewardsMock(alice.address, availableToClaim);
                await StakeManager.connect(alice).unstake();

                const aliceBalancesAfter = await getBalances(res, alice);
                
                const data = {
                    FRACTION: FRACTION,
                    duration: userStakeDuration,
                    defaultStakeDuration: defaultStakeDuration,
                    bonusSharesRate: bonusSharesRateIncreased,
                    amount: amountToStake
                };
                const expectedTokens = getShares(data);

                expect(aliceBalancesBefore.shares).to.eq(expectedTokens);
                expect(aliceBalancesAfter.shares).to.eq(0n);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(expectedShares);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(amountToStake);
            });

            it("should claim(only rewards)", async() => {
                const bonusMultiplier = 3n;
                const res = await deployStakingManagerWithBonus(bonusMultiplier);
                const {
                    alice,
                    defaultStakeDuration,
                    bonusSharesRateIncreased,
                    FRACTION,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = defaultStakeDuration*2n;
                await SimpleERC20.mint(alice, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                const aliceBalancesBefore = await getBalances(res, alice);
                
                const expectedShares = await StakeManager.connect(alice).calculateRewardsMock(alice.address, availableToClaim);
                await StakeManager.connect(alice).claim();

                const aliceBalancesAfter = await getBalances(res, alice);

                const data = {
                    FRACTION: FRACTION,
                    duration: userStakeDuration,
                    defaultStakeDuration: defaultStakeDuration,
                    bonusSharesRate: bonusSharesRateIncreased,
                    amount: amountToStake
                };
                const expectedTokens = getShares(data);

                expect(aliceBalancesBefore.shares).to.eq(expectedTokens);
                expect(aliceBalancesAfter.shares).to.eq(expectedTokens);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(expectedShares);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(0n);
            });
        });

        describe("with several users", function () {
            it("should stake", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    bob,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = 86400;
                await SimpleERC20.mint(alice, amountToStake);
                await SimpleERC20.mint(bob, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                const aliceBalancesBefore = await getBalances(res, alice);
                const bobBalancesBefore = await getBalances(res, bob);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await SimpleERC20.connect(bob).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(bob).stake(amountToStake, userStakeDuration);

                const aliceBalancesAfter = await getBalances(res, alice);
                const bobBalancesAfter = await getBalances(res, bob);

                expect(aliceBalancesBefore.shares).to.eq(0n);
                expect(aliceBalancesAfter.shares).to.eq(amountToStake);

                expect(aliceBalancesBefore.staked).to.eq(amountToStake);
                expect(aliceBalancesAfter.staked).to.eq(0n);

                expect(bobBalancesBefore.shares).to.eq(0n);
                expect(bobBalancesAfter.shares).to.eq(amountToStake);

                expect(bobBalancesBefore.staked).to.eq(amountToStake);
                expect(bobBalancesAfter.staked).to.eq(0n);
            });

            it("should unstake after making several stakes", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    bob,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = 86400;
                await SimpleERC20.mint(alice, amountToStake);
                await SimpleERC20.mint(bob, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await SimpleERC20.connect(bob).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(bob).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                const aliceBalancesBefore = await getBalances(res, alice);
                const bobBalancesBefore = await getBalances(res, bob);

                await StakeManager.connect(alice).unstake();
                const aliceBalancesAfter = await getBalances(res, alice);

                await StakeManager.connect(bob).unstake();
                const bobBalancesAfter = await getBalances(res, bob);

                // stake+stake - it's how many times called functions which increase tradedTokens amount
                // 2 times increasing availableToClaim
                // 2 person
                const expectClaimAmount = 2n * availableToClaim / 2n; // 2 - it how many users who stakes

                // 3 times increasing availableToClaim 
                // stake+stake+unstake
                const expectClaimAmountForSecondAttempt = 3n * availableToClaim / 2n; // 2 - it how many users who stakes

                expect(aliceBalancesBefore.shares).to.eq(amountToStake);
                expect(aliceBalancesAfter.shares).to.eq(0n);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(expectClaimAmount);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(amountToStake);
                //--------------------
                expect(bobBalancesBefore.shares).to.eq(amountToStake);
                expect(bobBalancesAfter.shares).to.eq(0n);

                expect(bobBalancesBefore.traded).to.eq(0n);
                expect(bobBalancesAfter.traded).to.eq(expectClaimAmountForSecondAttempt);

                expect(bobBalancesBefore.staked).to.eq(0n);
                expect(bobBalancesAfter.staked).to.eq(amountToStake);

            });

            it("should claim with simultaneously users who make stakes", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    bob,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = 86400;
                await SimpleERC20.mint(alice, amountToStake);
                await SimpleERC20.mint(bob, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await SimpleERC20.connect(bob).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(bob).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                const aliceBalancesBefore = await getBalances(res, alice);
                const bobBalancesBefore = await getBalances(res, bob);

                await StakeManager.connect(alice).claim();
                const aliceBalancesAfter = await getBalances(res, alice);

                // lastAccumulatedPerShare += availableToClaim / sharesTotal;
                // [startTime] lastAccumulatedPerShare = 0 + 1/1 = 1
                // lastAccumulatedPerShare = 1 + 1/2 = 1 + 0.5 = 1.5
                // [endTime] lastAccumulatedPerShare = 1.5 + 1/2 = 2
                // rewardsPerShare * st.shares = (accumulatedPerShare[endTime]-accumulatedPerShare[startTime]) * st.shares= (2-1) * 1 = 1*1 = 1;
                const aliceExpectClaimAmount = availableToClaim;

                expect(aliceBalancesBefore.shares).to.eq(amountToStake);
                expect(aliceBalancesAfter.shares).to.eq(amountToStake);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(aliceExpectClaimAmount);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(0n);
                


                await StakeManager.connect(bob).claim();
                const bobBalancesAfter = await getBalances(res, bob);
                // lastAccumulatedPerShare += availableToClaim / sharesTotal;
                // [startTime] lastAccumulatedPerShare = 1 + 1/1 = 1.5
                // lastAccumulatedPerShare = 1.5 + 1/2 = 1.5 + 0.5 = 2
                // [endTime] lastAccumulatedPerShare = 2 + 1/2 = 2.5
                // rewardsPerShare * st.shares = (accumulatedPerShare[endTime]-accumulatedPerShare[startTime]) * st.shares= (2.5-1.5) * 1 = 1*1 = 1;
                const bobExpectClaimAmount = availableToClaim;

                expect(bobBalancesBefore.shares).to.eq(amountToStake);
                expect(bobBalancesAfter.shares).to.eq(amountToStake);

                expect(bobBalancesBefore.traded).to.eq(0n);
                expect(bobBalancesAfter.traded).to.eq(bobExpectClaimAmount);

                expect(bobBalancesBefore.staked).to.eq(0n);
                expect(bobBalancesAfter.staked).to.eq(0n);

            });
            it("should claim after making several stakes", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStakeTotal = ethers.parseEther('10');
                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = 86400;
                await SimpleERC20.mint(alice, amountToStakeTotal);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStakeTotal);

                // stake 10 times, and between each other wait `userStakeDuration` time
                for (var i = 0; i < 10; i++) {
                    await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);
                    await time.increase(userStakeDuration);
                }

                const aliceBalancesBefore = await getBalances(res, alice);

                await StakeManager.connect(alice).claim();

                const aliceBalancesAfter = await getBalances(res, alice);

                // lastAccumulatedPerShare += availableToClaim / sharesTotal;
                //1 + 1.0/2+1.0/3+1.0/4+1.0/5+1.0/6+1.0/7+1.0/8+1.0/9+1.0/10+1.0/10
                //the last "1.0/10"  -  when claim
                var t = [];
                
                t[0] = 0n;
                for (var i = 1; i < 11; i++) {
                    t[i] = t[i-1] + availableToClaim/BigInt(i);
                }
                //the last "1.0/10"  -  when claim
                t[11] = t[10] + availableToClaim/BigInt(10);

                var accumulated = 0n;
                for (var i = 1; i < 12; i++) {
                    accumulated += t[11] - t[i];
                }

                expect(aliceBalancesBefore.shares).to.eq(amountToStakeTotal);
                expect(aliceBalancesAfter.shares).to.eq(amountToStakeTotal);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(accumulated);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(0n);
            });

        });
        describe("availableToClaim - can change", function () {
            it("should correctly unstake after making several stakes if TradedToken::availableToClaim will return 0", async() => {
                const res = await loadFixture(deployStakingManager);
                const {
                    alice,
                    bob,
                    SimpleERC20,
                    TradedTokenImitation,
                    StakeManager
                } = res;

                const amountToStake = ethers.parseEther('1');
                const availableToClaim = ethers.parseEther('1');
                const userStakeDuration = 86400;
                await SimpleERC20.mint(alice, amountToStake);
                await SimpleERC20.mint(bob, amountToStake);

                await TradedTokenImitation.setAvailableToClaim(availableToClaim);

                await SimpleERC20.connect(alice).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(alice).stake(amountToStake, userStakeDuration);

                await SimpleERC20.connect(bob).approve(StakeManager.target, amountToStake);
                await StakeManager.connect(bob).stake(amountToStake, userStakeDuration);

                await time.increase(userStakeDuration);

                const aliceBalancesBefore = await getBalances(res, alice);
                const bobBalancesBefore = await getBalances(res, bob);

                await TradedTokenImitation.setAvailableToClaim(0n);
                await StakeManager.connect(alice).unstake();
                const aliceBalancesAfter = await getBalances(res, alice);
                                
                //it's how many times called functions which increase tradedTokens amount
                
                // lastAccumulatedPerShare += availableToClaim / sharesTotal;
                // [startTime] lastAccumulatedPerShare = 0 + 1/1 = 1
                // lastAccumulatedPerShare = 1 + 1/2 = 1 + 0.5 = 1.5
                // [endTime] lastAccumulatedPerShare = 1.5 + 0/2 = 1.5
                // rewardsPerShare * st.shares = (accumulatedPerShare[startTime]-accumulatedPerShare[startTime]) * st.shares= (1.5-1) * 1 = 0.5*1 = 0.5;
                const aliceExpectClaimAmount = availableToClaim / 2n;

                expect(aliceBalancesBefore.shares).to.eq(amountToStake);
                expect(aliceBalancesAfter.shares).to.eq(0n);

                expect(aliceBalancesBefore.traded).to.eq(0n);
                expect(aliceBalancesAfter.traded).to.eq(aliceExpectClaimAmount);

                expect(aliceBalancesBefore.staked).to.eq(0n);
                expect(aliceBalancesAfter.staked).to.eq(amountToStake);

                
                // for bob it will be:
                // lastAccumulatedPerShare += availableToClaim / sharesTotal;
                // [startTime] lastAccumulatedPerShare = 1 + 1/2 = 1.5
                // lastAccumulatedPerShare = 1.5 + 0/1.5 = = 1.5
                // [endTime] lastAccumulatedPerShare = 1.5 + 0/1.5 = 1.5
                // rewardsPerShare * st.shares = (accumulatedPerShare[startTime]-accumulatedPerShare[startTime]) * st.shares= (1.5-1.5) * 1 = 0;
                const bobExpectClaimAmount = 0;
                await StakeManager.connect(bob).unstake();
                const bobBalancesAfter = await getBalances(res, bob);

                expect(bobBalancesBefore.shares).to.eq(amountToStake);
                expect(bobBalancesAfter.shares).to.eq(0n);

                expect(bobBalancesBefore.traded).to.eq(0n);
                expect(bobBalancesAfter.traded).to.eq(bobExpectClaimAmount);

                expect(bobBalancesBefore.staked).to.eq(0n);
                expect(bobBalancesAfter.staked).to.eq(amountToStake);

            });
        });
    });
    
});