const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-qbux.js');

async function main() {

	var signers = await ethers.getSigners();
	var deployer,
		deployer_auxiliary,
		deployer_releasemanager,
		deployer_itr,
		deployer_qbix,
		deployer_claim,
		deployer_stake;
	if (signers.length == 1) {
		deployer = signers[0];
		deployer_auxiliary = signers[0];
		deployer_releasemanager = signers[0];
		deployer_itr = signers[0];
		deployer_qbix = signers[0];
		deployer_claim = signers[0];
		deployer_stake = signers[0];
	} else {
		[
		deployer,
		deployer_auxiliary,
		deployer_releasemanager,
		deployer_itr,
		deployer_qbix,
		deployer_claim,
		deployer_stake
		] = signers;
	}

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log(
		"Deploying contracts with the account:",
		deployer_qbix.address
	);
	console.log("Account balance:", (await ethers.provider.getBalance(deployer_qbix.address)).toString());

	const networkName = hre.network.name;
	
	const libs = require('./libraries/'+networkName+'/list.js');

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});

	this.instance = await MainF.connect(deployer_qbix).deploy(...params);
	
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