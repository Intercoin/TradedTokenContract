const paramArguments = require('./arguments-itr.js');

async function main() {
   
	//const [deployer] = await ethers.getSigners();
	var signers = await ethers.getSigners();

    var deployer;
    if (signers.length == 1) {
        deployer = signers[0];
    } else {
        [,deployer,,,] = signers;
    }

	var options = {
		//gasPrice: ethers.utils.parseUnits('150', 'gwei'), 
		//gasLimit: 5e6
	};
	
	let params = [
		...paramArguments,
		options
	]

	console.log("Deploying contracts with the account:",deployer.address);
	console.log("Account balance:", (await deployer.getBalance()).toString());

  	const LiquidityManagerF = await ethers.getContractFactory("LiquidityManager");

	this.instance = await LiquidityManagerF.connect(deployer).deploy(...params);

	console.log("Was deployed at:", this.instance.address);
	console.log("with params:", [...paramArguments]);

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });