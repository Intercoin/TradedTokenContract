const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-qbix.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer;
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,,deployer_qbix] = signers;
    }


	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
	console.log(
		"Deploying contracts with the account:",
		deployer.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await deployer.getBalance()).toString());


	// const TaxesLib = await ethers.getContractFactory("TaxesLib");
	// const library = await TaxesLib.deploy();
	// await library.deployed();

	// const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
	// const library2 = await SwapSettingsLib.deploy();
	// await library2.deployed();

	// const MainF = await ethers.getContractFactory("TradedToken",  {
	// 	libraries: {
	// 		TaxesLib:library.address,
	// 		SwapSettingsLib:library2.address
	// 	}
	// });

	console.log(
		"Deploying contracts with the account:",
		deployer_qbix.address
	);
	console.log("Account balance:", (await deployer_qbix.getBalance()).toString());
	const networkName = hre.network.name;
	const libs = require('./libraries/'+networkName+'/list.js');

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib,
			SwapSettingsLib:libs.SwapSettingsLib
		}
	});

	this.instance = await MainF.connect(deployer_qbix).deploy(...params);
	
	console.log("Instance deployed at:", this.instance.address);
	console.log("with params:", [...paramArguments]);
	console.log("TaxesLib.library deployed at:", libs.TaxesLib);
	console.log("SwapSettingsLib.library deployed at:", libs.SwapSettingsLib);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });