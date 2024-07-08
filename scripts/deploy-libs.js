const fs = require('fs');
const hre = require('hardhat');


async function main() {

	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();
    var deployer, deployer_itr;
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,] = signers;
    }

	console.log(
		"Deploying contracts with the account:",
		deployer.address
	);

	console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.connect(deployer).deploy();
	await library.waitForDeployment();

	console.log("TaxesLib.library deployed at:", library.target);

    await hre.run("verify:verify", {
        address: library.target,
        constructorArguments: [],
      });
      

    const networkName = hre.network.name;
	
    console.log("put the following content into the file './libraries/"+networkName+"/list.js'");
    console.log("module.exports = {");
    console.log("     TaxesLib: \""+library.target+"\",");
    console.log("};");

  };
  

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });