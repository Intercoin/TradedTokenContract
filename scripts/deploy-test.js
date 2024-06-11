const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-test.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer;
	
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
		// for tests just use auxillary address. 
        [,deployer] = signers;
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

	console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.connect(deployer).deploy();
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