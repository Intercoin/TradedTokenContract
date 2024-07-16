const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-test.js');

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
//return;
	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
	console.log(
		"Deploying contracts with the account:",
		deployer.address
	);

	var options = {
		//gasPrice: ethers.parseUnits('27.5', 'gwei'), 
		//gasLimit: 5e6
		nonce: nonce
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.connect(deployer).deploy({nonce: nonce});
	await library.waitForDeployment();

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:library.target
		}
	});

	this.instance = await MainF.connect(deployer).deploy(...params);
	
	console.log("Instance deployed at:", this.instance.target);
	console.log("with params:", [...paramArguments]);
	console.log("TaxesLib.library deployed at:", library.target);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });