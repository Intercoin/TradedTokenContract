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
            } else {
            	resolve(data);
			}
        });
    });
}

async function main() {

	var data = await get_data();
    var data_object_root = JSON.parse(data);
	if (typeof data_object_root[hre.network.name] === 'undefined') {
		throw("Arguments file: missed data");
    } else if (typeof data_object_root[hre.network.name] === 'undefined') {
		throw("Arguments file: missed network data");
    }

	data_object = data_object_root[hre.network.name];

	if (
		typeof data_object.stakeManagerUpgradeable === 'undefined' ||
		!data_object.stakeManagerUpgradeable ||
		!data_object.releaseManager
	) {
		throw("Arguments file: wrong addresses");
	}
   
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
  	// const discountSensitivity = 0;

	var options = {
		//gasPrice: ethers.utils.parseUnits('150', 'gwei'), 
		//gasLimit: 5e6
	};
	let _params = [
		data_object.stakeManagerUpgradeable,
		ZERO_ADDRESS, // costmanager
		data_object.releaseManager
	]
	let params = [
		..._params,
		options
	]

	console.log("Deploying contracts with the account:",deployer_stake.address);
	console.log("Account balance:", (await ethers.provider.getBalance(deployer_stake.address)).toString());

  	const StakeManagerFactoryF = await ethers.getContractFactory("StakeManagerFactory");

	this.factory = await StakeManagerFactoryF.connect(deployer_stake).deploy(...params);

	await this.factory.waitForDeployment();

	console.log("Factory deployed at:", this.factory.target);
	console.log("with params:", [..._params]);

	console.log("registered with release manager:", data_object.releaseManager);

	const releaseManager = await ethers.getContractAt("ReleaseManager",data_object.releaseManager);
    let txNewRelease = await releaseManager.connect(deployer_releasemanager).newRelease(
        [this.factory.target], 
        [
            [
                27,//uint8 factoryIndex; 
                27,//uint16 releaseTag; 
                "0x53696c766572000000000000000000000000000000000000"//bytes24 factoryChangeNotes;
            ]
        ]
    );

    console.log('newRelease - waiting');
    await txNewRelease.wait(3);
    console.log('newRelease - mined');

	console.log("verifying");
    await hre.run("verify:verify", {address: this.factory.target, constructorArguments: _params});
	
}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });