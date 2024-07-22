const fs = require('fs');
const hre = require('hardhat');

async function main() {

	var signers = await ethers.getSigners();
    var deployer;
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,] = signers;
    }

	console.log(
		"Deploying contracts with the account:",
		deployer.address
	);

	console.log("Account balance:", (await deployer.getBalance()).toString());

    const TaxesLib = await ethers.getContractFactory("TaxesLib");
    const library = await TaxesLib.connect(deployer).deploy();
    await library.deployed();
    console.log("Account balance:", (await deployer.getBalance()).toString());
    const SwapSettingsLib = await ethers.getContractFactory("SwapSettingsLib");
    const library2 = await SwapSettingsLib.connect(deployer).deploy();
    await library2.deployed();
    console.log("Account balance:", (await deployer.getBalance()).toString());

    console.log("Account balance:", (await deployer.getBalance()).toString());	
	console.log("TaxesLib.library deployed at:", library.address);
	console.log("SwapSettingsLib.library deployed at:", library2.address);

    const networkName = hre.network.name;
    if (networkName == 'hardhat') {
        console.log("skipping verifying for  'hardhat' network");
    } else {
        console.log("Starting verifying:");
        await hre.run("verify:verify", {address: library.address, constructorArguments: []});
        await hre.run("verify:verify", {address: library2.address, constructorArguments: []});
    }
}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });