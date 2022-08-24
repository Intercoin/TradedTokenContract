const { ethers, waffle } = require('hardhat');
const { BigNumber } = require('ethers');
const { expect } = require('chai');
const chai = require('chai');
const { time } = require('@openzeppelin/test-helpers');


chai.use(require('chai-bignumber')());
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const DEAD_ADDRESS = '0x000000000000000000000000000000000000dEaD';

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
const ONE_DAY = BigNumber.from('86400');

const MAX_TOTAL_SUPPLY = BigNumber.from('200000000000000000000000000');

describe("ITR", function () {
    const accounts = waffle.provider.getWallets();

    const owner = accounts[0];                     
    const alice = accounts[1]; // account one
    const bob = accounts[2];  // account five

    const CLAIMED_DURATION = THREE.mul(TEN).mul(ONE_DAY);//2592000;
    const CLAIMED_FRACTION = TWO.mul(THOUSAND)
    const CLAIM_EXPECTED = THREE.mul(TEN).mul(THOUSAND).mul(ONE_ETH);
    const CLAIM_GROWTH = HUN;

    var ERC20MintableInstanceToken, ITRInstance;

     beforeEach("deploying", async() => {
        const ITRMock = await ethers.getContractFactory("ITRMock");
        const ERC20Mintable = await ethers.getContractFactory("ERC20Mintable");

        ERC20MintableInstanceToken = await ERC20Mintable.connect(bob).deploy("erc20testToken","erc20testToken");
        ITRInstance = await ITRMock.connect(bob).deploy();

    });

    it('check variables', async () => {
        let tmpTr = await ITRInstance.getClaimData();
        expect(tmpTr.addr).to.be.eq("0x6Ef5febbD2A56FAb23f18a69d3fB9F4E2A70440B");
        expect(tmpTr.duration).to.be.eq(CLAIMED_DURATION);
        expect(tmpTr.fraction).to.be.eq(CLAIMED_FRACTION);
        expect(tmpTr.excepted).to.be.eq(CLAIM_EXPECTED);
        expect(tmpTr.growth).to.be.eq(CLAIM_GROWTH);
        expect(await ITRInstance.getMaxTotalSupply()).to.be.eq(MAX_TOTAL_SUPPLY);
        expect(await ITRInstance.balanceOf(ITRInstance.address)).to.be.eq(ZERO);
        
    });
    
   
    it('claim test', async () => {
        let tmp;

        await ITRInstance.connect(owner).setClaimData(
            ERC20MintableInstanceToken.address,
            CLAIMED_DURATION,
            CLAIMED_FRACTION,
            CLAIM_EXPECTED,
            CLAIM_GROWTH
        );
        
        await expect(
            ITRInstance.connect(alice).claim(alice.address),
        ).to.be.revertedWith("nothing to claim");
        
        // emulate transfer tokens and make it's already in ITRInstance
        // let's claim too much than claimExcepted
        tmp = CLAIM_EXPECTED.mul(TWO);
        await ERC20MintableInstanceToken.connect(owner).mint(ITRInstance.address, tmp);
        
        //await expect().to.be.revertedWith("");
        await expect(
            ITRInstance.connect(owner).claim(alice.address)
        ).to.be.revertedWith("please claim less tokens per month");
        
        let claimedAmountBefore = await ITRInstance.connect(owner).getCurrentClaimedAmount();
        expect(claimedAmountBefore).to.be.eq(ZERO);
        
        await ERC20MintableInstanceToken.connect(owner).mint(alice.address, CLAIM_EXPECTED.mul(BigNumber.from('100000000000')));
        await ITRInstance.connect(owner).claim(alice.address);
        
        let claimedAmountAfter = await ITRInstance.connect(owner).getCurrentClaimedAmount();

        expect(claimedAmountAfter).to.be.eq(tmp);
        
        expect(await ITRInstance.balanceOf(alice.address)).to.be.eq(tmp);
        expect(await ERC20MintableInstanceToken.balanceOf(ITRInstance.address)).to.be.eq(ZERO);
        expect(await ERC20MintableInstanceToken.balanceOf(DEAD_ADDRESS)).to.be.eq(tmp);
        
        // let try again but emulated growing up  MAXclaimedAmount it will be 
        
        tmp = await ITRInstance.connect(owner).getMaxTotalSupply();
        await ITRInstance.connect(owner).setCurrentClaimedAmount(tmp);

        await ERC20MintableInstanceToken.connect(owner).mint(ITRInstance.address, CLAIM_EXPECTED);

        await expect(
            ITRInstance.connect(owner).claim(alice.address)
        ).to.be.revertedWith("please wait, too many tokens already claimed this month");
                                    
    });

    it('prevent claim over maxTotalSupply', async () => {
        await ITRInstance.connect(owner).setClaimData(
            ERC20MintableInstanceToken.address,
            CLAIMED_DURATION,
            BigNumber.from('1000000000000'),
            CLAIM_EXPECTED,
            CLAIM_GROWTH
        );
        await ITRInstance.connect(owner).setMaxTotalSupply(ONE_ETH);

        await ERC20MintableInstanceToken.connect(owner).mint(ITRInstance.address, TWO.mul(ONE_ETH));
        
        await expect(
            ITRInstance.connect(owner).claim(alice.address)
        ).to.be.revertedWith("this would exceed maxTotalSupply");
        
    });

});
