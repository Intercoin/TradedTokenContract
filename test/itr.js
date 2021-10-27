const BigNumber = require('bignumber.js');
const truffleAssert = require('truffle-assertions');

var ITRMock = artifacts.require("ITRMock");
const ERC20Mintable = artifacts.require("ERC20Mintable");
//const ERC777Mintable = artifacts.require("ERC777Mintable");

const helper = require("../helpers/truffleTestHelper");

require('@openzeppelin/test-helpers/configure')({ web3 });
const { singletons } = require('@openzeppelin/test-helpers');

contract('NFT', (accounts) => {
    
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
    var ITRInstance, ERC20MintableInstanceToken;
        
    var erc1820;
    let tmpTr;
    
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
        
        
        ERC20MintableInstanceToken = await ERC20Mintable.new("erc20testToken","erc20testToken", { from: accountFive });
        
        
        
    });
    
    beforeEach(async () => {
        ITRInstance = await ITRMock.new({ from: accountFive });
        // DividendsContractInstance = await DividendsContract.new({ from: accountFive });
        
        // await DividendsContractInstance.initialize('NFT-title', 'NFT-symbol', [CommunityMockInstance.address, "members"], { from: accountFive });
        
        // ERC20MintableInstance = await ERC20Mintable.new("erc20test","erc20test",{ from: accountFive });
    });

    it('check variables', async () => {
        tmpTr = await ITRInstance.getClaimData();
        assert.equal(tmpTr.addr, 0x6Ef5febbD2A56FAb23f18a69d3fB9F4E2A70440B, "Addr wrong");
        assert.equal(tmpTr.duration.toString(), claimedDuration.toString(), "duration wrong");
        assert.equal(tmpTr.fraction.toString(), claimedFraction.toString(), "fraction wrong");
        assert.equal(BigNumber(tmpTr.excepted).toString(), BigNumber(claimExcepted).toString(), "claimExcepted wrong");
        assert.equal(tmpTr.growth.toString(), claimGrowth.toString(), "claimGrowth wrong");
        assert.equal(
            (
            await ITRInstance.getMaxTotalSupply()
            ).toString(), 
            '200000000000000000000000000', "MaxTotalSupply is wrong");
            assert.equal(
            (
            await ITRInstance.balanceOf(ITRInstance.address)
            ).toString(), 
            '0', "ITRInstance balance is wrong");
    });
    
    it('claim test', async () => {
        let tmp;
        await ITRInstance.setClaimData(
            ERC20MintableInstanceToken.address,
            claimedDuration,
            claimedFraction,
            claimExcepted,
            claimGrowth
        );
        
        await truffleAssert.reverts(
            ITRInstance.claim(accountOne, {from: accountOne}),
            'nothing to claim'
        );
        
        // emulate transfer tokens and make it's already in ITRInstance
        // let's claim too much than claimExcepted
        tmp = BigNumber(claimExcepted).times(2);
        await ERC20MintableInstanceToken.mint(ITRInstance.address, (tmp));
        //await ERC20MintableInstanceToken.mint(accountOne, (tmp));
        
        await truffleAssert.reverts(
            ITRInstance.claim(accountOne),
            "please claim less tokens or wait longer for them to be unlocked"
        );
        
        let claimedAmountBefore = await ITRInstance.getCurrentClaimedAmount();
        assert.equal(claimedAmountBefore.toString(), '0', "claimedAmountBefore wrong");
        
        
        await ERC20MintableInstanceToken.mint(accountOne, BigNumber(claimExcepted).times(100000000000));
        await ITRInstance.claim(accountOne);
        
        let claimedAmountAfter = await ITRInstance.getCurrentClaimedAmount();
        assert.equal(
            BigNumber(claimedAmountAfter).toString(), 
            BigNumber(tmp).toString(), 
            "claimedAmountAfter wrong"
            );
        
        assert.equal(
            BigNumber(await ITRInstance.balanceOf(accountOne)).toString(), 
            BigNumber(tmp).toString(), 
            "can get ITR tokens after claim"
        );
        assert.equal(
            BigNumber(await ERC20MintableInstanceToken.balanceOf(ITRInstance.address)).toString(), 
            '0', 
            "can get ITR tokens after claim"
        );
        
        assert.equal(
            BigNumber(await ERC20MintableInstanceToken.balanceOf(deadAddress)).toString(), 
            BigNumber(tmp).toString(), 
            "Claimed tokens dos not move to deadAddress"
        );
        
        // let try again but emulated growing up  MAXclaimedAmount it will be 
        
        tmp = await ITRInstance.getMaxTotalSupply();
        await ITRInstance.setCurrentClaimedAmount(tmp);

        await ERC20MintableInstanceToken.mint(ITRInstance.address, (claimExcepted));

        await truffleAssert.reverts(
            ITRInstance.claim(accountOne),
            "please wait, too many tokens already claimed during this time period"
        );
        
    });

    it('prevent claim over maxTotalSupply', async () => {
        await ITRInstance.setClaimData(
            ERC20MintableInstanceToken.address,
            claimedDuration,
            1000000000000,
            claimExcepted,
            claimGrowth
        );
        await ITRInstance.setMaxTotalSupply(oneToken);

        await ERC20MintableInstanceToken.mint(ITRInstance.address, BigNumber(twoToken));
        
        await truffleAssert.reverts(
            ITRInstance.claim(accountOne),
            "this would exceed maxTotalSupply"
        );
        
    });
});