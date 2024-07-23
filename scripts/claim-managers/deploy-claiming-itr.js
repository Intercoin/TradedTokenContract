const fs = require('fs');
const hre = require('hardhat');
const paramITRArguments = require('./arguments-claiming-itr.js');

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
	if (typeof data_object_root[hre.network.name] === 'undefined') {
		throw("Arguments file: missed data");
    } else if (typeof data_object_root[hre.network.name] === 'undefined') {
		throw("Arguments file: missed network data");
    }

	data_object = data_object_root[hre.network.name];

	var signers = await ethers.getSigners();
	var deployer,
		deployer_auxiliary,
		deployer_releasemanager,
		deployer_itr,
		deployer_qbix,
		deployer_claim,
		deployer_stake,
        deployer_claiming_itr,
        deployer_claiming_qbix;
	if (signers.length == 1) {
		deployer = signers[0];
		deployer_auxiliary = signers[0];
		deployer_releasemanager = signers[0];
		deployer_itr = signers[0];
		deployer_qbix = signers[0];
		deployer_claim = signers[0];
		deployer_stake = signers[0];
        deployer_claiming_itr = signers[0];
        deployer_claiming_qbix = signers[0];
	} else {
		[
		deployer,
		deployer_auxiliary,
		deployer_releasemanager,
		deployer_itr,
		deployer_qbix,
		deployer_claim,
		deployer_stake,
        deployer_claiming_itr,
        deployer_claiming_qbix
		] = signers;
	}

	console.log(
		"Deploying contracts with the account:",
		deployer_claiming_itr.address
	);

	console.log("Account balance:", (await ethers.provider.getBalance(deployer_claiming_itr.address)).toString());
    
    const claimingTokenF = await ethers.getContractFactory("ClaimingToken");
    const claimingTokenITR = await claimingTokenF.connect(deployer_claiming_itr).deploy(...paramITRArguments);

    await claimingTokenITR.waitForDeployment();

    data_object.claimingTokenITR = claimingTokenITR.target;
	//---
	const ts_updated = Date.now();
    data_object.time_updated = ts_updated;
    data_object_root[`${hre.network.name}`] = data_object;
    data_object_root.time_updated = ts_updated;
    let data_to_write = JSON.stringify(data_object_root, null, 2);
	console.log(data_to_write);
    await write_data(data_to_write);

    console.log("claimingTokenITR deployed at:", claimingTokenITR.target);
    
    const networkName = hre.network.name;
    if (networkName == 'hardhat') {
        console.log("skipping verifying for  'hardhat' network");
    } else {
        console.log("Starting verifying:");

        await hre.run("verify:verify", {
            address: claimingTokenITR.target,
            constructorArguments: [...paramITRArguments],
        });
    }

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });