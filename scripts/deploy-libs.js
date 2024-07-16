const fs = require('fs');
const hre = require('hardhat');


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

	console.log(
		"Deploying contracts with the account:",
		deployer_auxiliary.address
	);

	console.log("Account balance:", (await ethers.provider.getBalance(deployer_auxiliary.address)).toString());

	const TaxesLib = await ethers.getContractFactory("TaxesLib");
	const library = await TaxesLib.connect(deployer_auxiliary).deploy();
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