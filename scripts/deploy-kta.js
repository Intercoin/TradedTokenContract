const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-kta.js');
const chainIdConverter = require('./helpers/chainIdConverter.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer, deployer_itr, deployer_kta;

    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,,,,deployer_kta] = signers;
    }


	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
	console.log(
		"Deploying contracts with the account:",
		deployer_kta.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await deployer_kta.getBalance()).toString());

// 	const TaxesLib = await ethers.getContractFactory("TaxesLib");
// 	const library = await TaxesLib.connect(deployer).deploy();
// 	await library.deployed();
// console.log("Account balance:", (await deployer.getBalance()).toString());
// 	const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
// 	const library2 = await SwapSettingsLib.connect(deployer).deploy();
// 	await library2.deployed();
// console.log("Account balance:", (await deployer.getBalance()).toString());

	// const MainF = await ethers.getContractFactory("TradedToken",  {
	// 	libraries: {
	// 		TaxesLib:library.address,
	// 		SwapSettingsLib:library2.address
	// 	}
	// });


	//const networkName = hre.network.name;
    const chainId = hre.network.config.chainId;
    // here can be fork in localhost and network can be localhost.  so just did converted  chainIdto network name
    const networkName = chainIdConverter.chainIDToNetworkName(chainId);
    
	const libs = require('./libraries/'+networkName+'/list.js');
	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib,
			SwapSettingsLib:libs.SwapSettingsLib
		}
	});
	
	this.instance = await MainF.connect(deployer_kta).deploy(...params);
	
	console.log("Account balance:", (await deployer_kta.getBalance()).toString());	
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