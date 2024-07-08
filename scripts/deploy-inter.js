const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-inter.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer, deployer_itr;
    if (signers.length == 1) {
        deployer_itr = signers[0];
    } else {
        [,deployer,deployer_itr] = signers;
    }

	console.log(
		"Deploying contracts with the account:",
		deployer_itr.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await ethers.provider.getBalance(deployer_itr.address)).toString());

	const networkName = hre.network.name;
	
	const libs = require('./libraries/'+networkName+'/list.js');

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});


	this.instance = await MainF.connect(deployer_itr).deploy(...params);

	await this.instance.waitForDeployment();
	
	console.log("Instance deployed at:", this.instance.target);
	console.log("with params:", [...paramArguments]);
	console.log("TaxesLib.library deployed at:", libs.TaxesLib);

	await hre.run("verify:verify", {
		address: this.instance.target,
		constructorArguments: paramArguments,
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });