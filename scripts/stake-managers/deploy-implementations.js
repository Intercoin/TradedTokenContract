const fs = require('fs');
//const HDWalletProvider = require('truffle-hdwallet-provider');

function get_data(_message) {
    return new Promise(function(resolve, reject) {
        fs.readFile('./scripts/arguments.json', (err, data) => {
            if (err) {
                if (err.code == 'ENOENT' && err.syscall == 'open' && err.errno == -4058) {
                    let obj = {};
					data = JSON.stringify(obj, null, "");
                    fs.writeFile('./scripts/arguments.json', data, (err) => {
                        if (err) throw err;
                        resolve(data);
                    });
                } else {
                    throw err;
                }
            }
    
            resolve(data);
        });
    });
}

function write_data(_message) {
    return new Promise(function(resolve, reject) {
        fs.writeFile('./scripts/arguments.json', _message, (err) => {
            if (err) throw err;
            console.log('Data written to file');
            resolve();
        });
    });
}

async function main() {
	var data = await get_data();

    var data_object_root = JSON.parse(data);
	var data_object = {};
	if (typeof data_object_root[hre.network.name] === 'undefined') {
        data_object.time_created = Date.now()
    } else {
        data_object = data_object_root[hre.network.name];
    }
	//----------------

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

	const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
    const RELEASE_MANAGER = hre.network.name == 'polygonMumbai'? process.env.RELEASE_MANAGER_MUMBAI : process.env.RELEASE_MANAGER;
	console.log(
		"Deploying contracts with the account:",
		deployer_auxiliary.address
	);

	// var options = {
	// 	//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
	// 	gasLimit: 10e6
	// };

	const deployerBalanceBefore = await ethers.provider.getBalance(deployer_auxiliary.address);
    console.log("Account balance:", (deployerBalanceBefore).toString());

    const stakeManagerUpgradeableF = await ethers.getContractFactory("StakeManagerUpgradeable");

	const stakeManagerUpgradeable = await stakeManagerUpgradeableF.connect(deployer_auxiliary).deploy();

	await stakeManagerUpgradeable.waitForDeployment();
    
	console.log("Implementations:");
	console.log("  stakeManagerUpgradeable deployed at:       ", stakeManagerUpgradeable.address);
    console.log("Linked with manager:");
    console.log("  Release manager:", RELEASE_MANAGER);

	data_object.stakeManagerUpgradeable 		    = stakeManagerUpgradeable.target;
	
    data_object.releaseManager  = RELEASE_MANAGER;
    
    const deployerBalanceAfter = await ethers.provider.getBalance(deployer_auxiliary.address);
    console.log("Spent:", ethers.formatEther(deployerBalanceBefore - deployerBalanceAfter));
    console.log("gasPrice:", ethers.formatUnits((await network.provider.send("eth_gasPrice")), "gwei")," gwei");

	//---
	const ts_updated = Date.now();
    data_object.time_updated = ts_updated;
    data_object_root[`${hre.network.name}`] = data_object;
    data_object_root.time_updated = ts_updated;
    let data_to_write = JSON.stringify(data_object_root, null, 2);
	console.log(data_to_write);
    await write_data(data_to_write);

	console.log("verifying");
    await hre.run("verify:verify", {address: data_object.stakeManagerUpgradeable, constructorArguments: []});
}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });