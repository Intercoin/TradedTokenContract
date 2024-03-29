const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-itr.js');

async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer, deployer_itr;
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,deployer_itr] = signers;
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

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.connect(deployer).deploy();
	await library.deployed();
console.log("Account balance:", (await deployer.getBalance()).toString());
	const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
	const library2 = await SwapSettingsLib.connect(deployer).deploy();
	await library2.deployed();
console.log("Account balance:", (await deployer.getBalance()).toString());
	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:library.address,
			SwapSettingsLib:library2.address
		}
	});


	this.instance = await MainF.connect(deployer_itr).deploy(...params);
console.log("Account balance:", (await deployer.getBalance()).toString());	
	console.log("Instance deployed at:", this.instance.address);
	console.log("with params:", [...paramArguments]);
	console.log("TaxesLib.library deployed at:", library.address);
	console.log("SwapSettingsLib.library deployed at:", library2.address);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });