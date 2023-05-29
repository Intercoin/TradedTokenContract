const fs = require('fs');
const hre = require('hardhat');
//const HDWalletProvider = require('truffle-hdwallet-provider');
async function getBUSDAddress() {

	const networkName = hre.network.name;
	const chainId = hre.network.config.chainId;

	//see https://cryptorank.io/price/binance-usd
	if ((networkName == 'bsc') && (chainId == 56)) {
		return "0xe9e7cea3dedca5984780bafc599bd69add087d56";
	} else if ((networkName == 'mumbai') && (chainId == 80001)) {
		return "0x9fb83c0635de2e815fd1c21b3a292277540c2e8d";
	} else if ((networkName == 'matic') && (chainId == 137)) {
		return "0x9fb83c0635de2e815fd1c21b3a292277540c2e8d";
	} else if ((networkName == 'mainnet') && (chainId == 1)) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53";
	} else if ((networkName == 'hardhat')) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53"; // use
	} else {

		throw "unknown network for grab busd token | networkName=`"+networkName+"`; chainId=`"+chainId+"`";
	}
	
}
async function main() {

	const [deployer] = await ethers.getSigners();



	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
	console.log(
		"Deploying contracts with the account:",
		deployer.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};
	/*
tokenName: "Intercoin"
tokenSymbol: "ITR"
reserveToken: BUSD (find it on BNB)  
... please check if people with BNB on pancakeswap can easily swap to any token through BNB -> BUSD -> token, right away ... like actually try it with a tiny amount of BNB
otherwise the reserveToken would be 0x0
priceDrop: 10000 (10%)
lockupIntervalAmount: 1 year
minClaimPrice: 10 cents in BUSD which is the initial price
externalToken: 0x0 (don't require external token, to mint more)
externalTokenExchangePrice: 1 (or whatever, since we don't have external token)
buyTaxMax: 10000 (10%)
sellTaxMax: 10000 (10%)

*/
	let bUSD = await getBUSDAddress();
	//const FRACTION = 10000;
	let _params = [
		"Intercoin-Test", // string memory tokenName_,
        "ITRt",// string memory tokenSymbol_,
        bUSD, // address reserveToken_, //” (USDC)
        1000, // uint256 priceDrop_,
        365,// uint64 lockupIntervalAmount_,
		// TradedToken.ClaimSettings memory claimSettings,
		[
			[1,10], // PriceNumDen minClaimPrice;
			[1,10], // PriceNumDen minClaimPriceGrow;
		],
		// TaxesLib.TaxesInfoInit memory taxesInfoInit,
		[
			0, //uint16 buyTaxDuration;
			0, //uint16 sellTaxDuration;
			false, //bool buyTaxGradual;
			false //bool sellTaxGradual;
		],
		//RateLimit memory panicSellRateLimit_,
		//And panicSell globally is max 10% in a day 
		[ // means no limit
			86400, // uint32 duration;  
        	1000 // uint32 fraction; 
		],
        1000, // uint256 buyTaxMax_,
        1000, // uint256 sellTaxMax_
		10 //holdersMax
	];
	
	let params = [
		..._params,
		options
	];

	console.log("Account balance:", (await deployer.getBalance()).toString());

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.deploy();
	await library.deployed();

	const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
	const library2 = await SwapSettingsLib.deploy();
	await library2.deployed();

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:library.address,
			SwapSettingsLib:library2.address
		}
	});

console.log([...params]);
	this.instance = await MainF.connect(deployer).deploy(...params);
	
	console.log("Instance deployed at:", this.instance.address);
	console.log("with params:", [..._params]);
	console.log("TaxesLib.library deployed at:", library.address);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });