const BigNumber = require('bignumber.js');
const truffleAssert = require('truffle-assertions');

var ITRMock = artifacts.require("ITRMock");
const MockSRC20 = artifacts.require("MockSRC20");
const TransferRule = artifacts.require("TransferRule");
const ChainRuleMock1 = artifacts.require("ChainRuleMock1");
const ChainRuleMock2 = artifacts.require("ChainRuleMock2");
const ChainRuleMock3 = artifacts.require("ChainRuleMock3");

var ERC20Mintable = artifacts.require("ERC20Mintable");

const helper = require("../helpers/truffleTestHelper");

require('@openzeppelin/test-helpers/configure')({ web3 });
const { singletons } = require('@openzeppelin/test-helpers');

contract('Transfer Rule', (accounts) => {
    
    // Setup accounts.
    const accountOne = accounts[0];
    const accountTwo = accounts[1];
    const accountThree = accounts[2];
    const accountFourth = accounts[3];
    const accountFive = accounts[4];
    const accountSix = accounts[5];
    const accountSeven = accounts[6];
    const accountEight = accounts[7];
    const accountNine = accounts[8];
    const accountTen = accounts[9];
    
    const zeroAddress = "0x0000000000000000000000000000000000000000";
    const deadAddress = "0x000000000000000000000000000000000000dEaD";
    
    //const noneExistTokenID = '99999999';
    const oneToken = "1000000000000000000";
    const twoToken = "2000000000000000000";
    const oneToken07 = "700000000000000000";
    const oneToken05 = "500000000000000000";    
    const oneToken03 = "300000000000000000";    
    var ITRInstance, ERC20MintableInstanceToken, MockSRC20Instance, TransferRuleInstance;
        
    var erc1820;
    let tmpTr;
    
    var lockupDuration = 604800;
    var lockupFraction = 90000;
    
    
    var claimedDuration = 2592000;
    var claimedFraction = 2000;
    var claimExcepted = BigNumber(30000).times(BigNumber(10**18));
    var claimGrowth = 100;
    
    function getArgs(tr, eventname) {
        for (var i in tmpTr.logs) {
            if (eventname == tmpTr.logs[i].event) {
                return tmpTr.logs[i].args;
            }
        }
        return '';
    }
    
    before(async () => {
        erc1820 = await singletons.ERC1820Registry(accountNine);

    });
    
    beforeEach(async () => {
        //ERC20MintableInstanceToken = await ERC20Mintable.new("erc20testToken","erc20testToken", { from: accountFive });
        
        ITRInstance = await ITRMock.new({ from: accountFive });
        
        TransferRuleInstance = await TransferRule.new(ITRInstance.address, lockupDuration, lockupFraction, { from: accountTen });
        
        MockSRC20Instance = await MockSRC20.new({ from: accountTen });
        
        await MockSRC20Instance.updateRestrictionsAndRules(zeroAddress, TransferRuleInstance.address, { from: accountTen });
        
    });

    it('setERC test', async () => {
        await TransferRuleInstance.cleanSRC({ from: accountTen });
        await MockSRC20Instance.updateRestrictionsAndRules(zeroAddress, zeroAddress, { from: accountTen });
        
        await MockSRC20Instance.updateRestrictionsAndRules(zeroAddress, TransferRuleInstance.address, { from: accountTen });
        
        await truffleAssert.reverts(
            MockSRC20Instance.updateRestrictionsAndRules(zeroAddress, TransferRuleInstance.address, { from: accountTen }),
            'external contract already set'
        );

    });
    
    it('should exchange', async () => {
        
        await ITRInstance.setClaimData(
            MockSRC20Instance.address,
            claimedDuration,
            claimedFraction,
            claimExcepted,
            claimGrowth
        );
        // premint
        tmp = BigNumber(claimExcepted).times(100000000000);
        await MockSRC20Instance.mint(accountOne, tmp);

        let balanceBefore = await ITRInstance.balanceOf(accountOne);
        tmp = BigNumber(claimExcepted).times(2);
        await MockSRC20Instance.transfer(ITRInstance.address, tmp, {from: accountOne});
        
        let balanceAfter = await ITRInstance.balanceOf(accountOne);
        
        assert.equal(
            BigNumber(balanceAfter).minus(BigNumber(balanceBefore)).toString(),
            BigNumber(tmp).toString(),
            "wrong exchange"
        )
        
    });
    
    it('check chains if chain revert', async () => {
        
        let chain1Instance = await ChainRuleMock1.new({from: accountOne});
        await TransferRuleInstance.setChain(chain1Instance.address, { from: accountTen });
        
        await chain1Instance.setRevertState(true);
        
        await ITRInstance.setClaimData(
            MockSRC20Instance.address,
            claimedDuration,
            claimedFraction,
            claimExcepted,
            claimGrowth
        );
        
        // premint
        tmp = BigNumber(claimExcepted).times(100000000000);
        await MockSRC20Instance.mint(accountOne, tmp);
        
        let balanceBefore = await ITRInstance.balanceOf(accountOne);
        
        tmp = BigNumber(claimExcepted).times(2);
        await truffleAssert.reverts(
            MockSRC20Instance.transfer(ITRInstance.address, tmp, {from: accountOne}),
            'ShouldRevert#1'
        );
        
        // if chain will remove then exchange went as expected 
        await TransferRuleInstance.clearChain({ from: accountTen });
        // ------------
        
        await MockSRC20Instance.transfer(ITRInstance.address, tmp, {from: accountOne});
        
        let balanceAfter = await ITRInstance.balanceOf(accountOne);
        
        assert.equal(
            BigNumber(balanceAfter).minus(BigNumber(balanceBefore)).toString(),
            BigNumber(tmp).toString(),
            "wrong exchange"
        )
    });
    
    /*
    it('locked up secondary exchange', async () => {
        // premint
        await MockSRC20Instance.mint(accountOne, BigNumber(oneToken).times(11));
        
        // exchange to new ITR send to ITRInstance
        await MockSRC20Instance.transfer(ITRInstance.address, BigNumber(oneToken), {from: accountOne});
        
        await truffleAssert.reverts(
            MockSRC20Instance.transfer(ITRInstance.address, BigNumber(oneToken), {from: accountOne}),
            "you recently claimed new tokens, please wait until duration has elapsed to claim again"
        );
        
    });
    
    
    it('usual transfer free tokens after exchange and locked others', async () => {
        // premint
        await MockSRC20Instance.mint(accountOne, BigNumber(oneToken).times(11));
        
        // exchange to new ITR send to ITRInstance
        await MockSRC20Instance.transfer(ITRInstance.address, BigNumber(oneToken), {from: accountOne});
        
        // again to another account -  ok   it' 10 %
        await MockSRC20Instance.transfer(accountTwo, BigNumber(oneToken), {from: accountOne});
        
        // any transfer will locked
        await truffleAssert.reverts(
            MockSRC20Instance.transfer(accountTwo, BigNumber(oneToken), {from: accountOne}),
            "you recently claimed new tokens, please wait until duration has elapsed to transfer this many tokens"
        );
    });
    */
    // it('check variables', async () => {
    //     tmpTr = await ITRInstance.getClaimData();
    //     assert.equal(tmpTr.addr, 0x6Ef5febbD2A56FAb23f18a69d3fB9F4E2A70440B, "Addr wrong");
    //     assert.equal(tmpTr.duration.toString(), claimedDuration.toString(), "duration wrong");
    //     assert.equal(tmpTr.fraction.toString(), claimedFraction.toString(), "fraction wrong");
    //     assert.equal(BigNumber(tmpTr.excepted).toString(), BigNumber(claimExcepted).toString(), "claimExcepted wrong");
    //     assert.equal(tmpTr.growth.toString(), claimGrowth.toString(), "claimGrowth wrong");
    //     assert.equal(
    //         (
    //         await ITRInstance.getMaxTotalSupply()
    //         ).toString(), 
    //         '200000000000000000000000000', "MaxTotalSupply is wrong");
    //         assert.equal(
    //         (
    //         await ITRInstance.balanceOf(ITRInstance.address)
    //         ).toString(), 
    //         '0', "ITRInstance balance is wrong");
    // });
    
    // it('claim test', async () => {
    //     let tmp;
    //     await ITRInstance.setClaimData(
    //         ERC20MintableInstanceToken.address,
    //         claimedDuration,
    //         claimedFraction,
    //         claimExcepted,
    //         claimGrowth
    //     );
        
    //     await truffleAssert.reverts(
    //         ITRInstance.claim(accountOne, {from: accountOne}),
    //         'nothing to claim'
    //     );
        
    //     // emulate transfer tokens and make it's already in ITRInstance
    //     // let's claim too much than claimExcepted
    //     tmp = BigNumber(claimExcepted).times(2);
    //     await ERC20MintableInstanceToken.mint(ITRInstance.address, (tmp));
    //     //await ERC20MintableInstanceToken.mint(accountOne, (tmp));
        
    //     await truffleAssert.reverts(
    //         ITRInstance.claim(accountOne),
    //         "please claim less tokens or wait longer for them to be unlocked"
    //     );
        
    //     let claimedAmountBefore = await ITRInstance.getCurrentClaimedAmount();
    //     assert.equal(claimedAmountBefore.toString(), '0', "claimedAmountBefore wrong");
        
        
    //     await ERC20MintableInstanceToken.mint(accountOne, BigNumber(claimExcepted).times(100000000000));
    //     await ITRInstance.claim(accountOne);
        
    //     let claimedAmountAfter = await ITRInstance.getCurrentClaimedAmount();
    //     assert.equal(
    //         BigNumber(claimedAmountAfter).toString(), 
    //         BigNumber(tmp).toString(), 
    //         "claimedAmountAfter wrong"
    //         );
        
    //     assert.equal(
    //         BigNumber(await ITRInstance.balanceOf(accountOne)).toString(), 
    //         BigNumber(tmp).toString(), 
    //         "can get ITR tokens after claim"
    //     );
    //     assert.equal(
    //         BigNumber(await ERC20MintableInstanceToken.balanceOf(ITRInstance.address)).toString(), 
    //         '0', 
    //         "can get ITR tokens after claim"
    //     );
        
    //     assert.equal(
    //         BigNumber(await ERC20MintableInstanceToken.balanceOf(deadAddress)).toString(), 
    //         BigNumber(tmp).toString(), 
    //         "Claimed tokens dos not move to deadAddress"
    //     );
        
    //     // let try again but emulated growing up  MAXclaimedAmount it will be 
        
    //     tmp = await ITRInstance.getMaxTotalSupply();
    //     await ITRInstance.setCurrentClaimedAmount(tmp);

    //     await ERC20MintableInstanceToken.mint(ITRInstance.address, (claimExcepted));

    //     await truffleAssert.reverts(
    //         ITRInstance.claim(accountOne),
    //         "please wait, too many tokens already claimed during this time period"
    //     );
        
    // });

    // it('prevent claim over maxTotalSupply', async () => {
    //     await ITRInstance.setClaimData(
    //         ERC20MintableInstanceToken.address,
    //         claimedDuration,
    //         1000000000000,
    //         claimExcepted,
    //         claimGrowth
    //     );
    //     await ITRInstance.setMaxTotalSupply(oneToken);

    //     await ERC20MintableInstanceToken.mint(ITRInstance.address, BigNumber(twoToken));
        
    //     await truffleAssert.reverts(
    //         ITRInstance.claim(accountOne),
    //         "this would exceed maxTotalSupply"
    //     );
        
    // });
});