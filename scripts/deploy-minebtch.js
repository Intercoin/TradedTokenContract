const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-minebtch.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer_auxiliary;
    if (signers.length == 1) {
        deployer_auxiliary = signers[0];
    } else {
        [,deployer_auxiliary] = signers;
    }

	console.log(
		"Deploying contracts with the account:",
		deployer_auxiliary.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await deployer_auxiliary.getBalance()).toString());

	const networkName = hre.network.name;
	const libs = require('./libraries/'+networkName+'/list.js');
	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib,
			SwapSettingsLib:libs.SwapSettingsLib
		}
	});
	
	this.instance = await MainF.connect(deployer_auxiliary).deploy(...params);
	
	console.log("Account balance:", (await deployer_auxiliary.getBalance()).toString());	
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