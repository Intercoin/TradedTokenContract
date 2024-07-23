const fs = require('fs');
const hre = require('hardhat');

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

	if (
		typeof data_object.claimManagerFactory === 'undefined' ||
        typeof data_object.claimingTokenITR === 'undefined' ||
        typeof data_object.claimingTokenQBIX === 'undefined' ||
		!data_object.claimManagerFactory ||
		!data_object.claimingTokenITR ||
		!data_object.claimingTokenQBIX
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
    console.log("@dev: script is not stable. can get claiming instance address from event. rc.logs are undefined. i don't know why, but TX IS SUCCESSFUL");
	console.log(
		"Deploying contracts with the account:",
		deployer_claim.address
	);

/**/
	console.log("Account balance:", (await ethers.provider.getBalance(deployer_claim.address)).toString());
    
    let tx,tx2;
    //const claimManagerFactory = await ethers.getContractAt("ClaimManagerFactory", data_object.claimManagerFactory);
    const claimManagerFactoryF = await ethers.getContractFactory("ClaimManagerFactory");
    const claimManagerFactory = await claimManagerFactoryF.attach(data_object.claimManagerFactory);
    
    const claimingToken1 = data_object.claimingTokenITR; // 
    const tradedToken1 = "0x1117d11930a11d2e36eff79e47ac92d25551b155"; //ITR(CERTIK)

    const claimingToken2 = data_object.claimingTokenQBIX; // 
    const tradedToken2 = "0xfaced1a6dc5d064ba397cb9be8c6cd666b8ddabb"; //QBIX(CERTIK)
    
    const claimingTokenArgs1 = [
        //address tradedToken,
        tradedToken1, 
        //IClaimUpgradeable.ClaimSettings memory claimSettings
        [
            claimingToken1, // ITR(CERTIK)
            [1,1],  // 1
            604800  //WEEK
        ]
    ];
    const claimingTokenArgs2 = [
        //address tradedToken,
        tradedToken2, 
        //IClaimUpgradeable.ClaimSettings memory claimSettings
        [
            claimingToken2, // QBIX(CERTIK)
            [1,1],  // 1
            604800  //WEEK
        ]
    ];

    tx = await claimManagerFactory.connect(deployer_claim).produce(...claimingTokenArgs1);
    tx2 = await claimManagerFactory.connect(deployer_claim).produce(...claimingTokenArgs2);

    // await tx.wait();
    // await tx2.wait();

    var rc, event,instance;
    rc = await tx.wait(3); // 0ms, as tx is already confirmed
    event = rc.logs.find(event => event.fragment && event.fragment.name === 'InstanceCreated');

    [instance,] = event.args;
    const claimManagerAddress1 = instance;
    //-----
    rc = await tx2.wait(3); // 0ms, as tx is already confirmed
    event = rc.logs.find(event => event.fragment && event.fragment.name === 'InstanceCreated');
    [instance,] = event.args;
    const claimManagerAddress2 = instance;
    //------------

    const distributionManagerF = await ethers.getContractFactory("DistributionManager");
    const distributionManager2 = await distributionManagerF.connect(deployer_auxiliary).deploy(
        // address claiming, 
        claimingToken2,
        // address manager
        claimManagerAddress2
    );

    await distributionManager2.waitForDeployment();
	
    console.log("claimManagerAddress1 deployed at:", claimManagerAddress1.target);

    console.log("distributionManager2 deployed at:", distributionManager2.target);
    console.log("claimManagerAddress2 deployed at:", claimManagerAddress2.target);
/**/
    
// const distributionManager2 = {target: '0xDccF4f25BDd5937e74E7D8fE4dA6975540D69148'};
// const claimingToken2 = '0x0000000069361B69110b190003D0220B38976D60';
// const claimManagerAddress2 = '0x54717897a1e9690D4b5cd025D2607F75D812564D';
    const networkName = hre.network.name;
    if (networkName == 'hardhat') {
        console.log("skipping verifying for  'hardhat' network");
    } else {
        console.log("Starting verifying:");

        await hre.run("verify:verify", {
            address: distributionManager2.target,
            constructorArguments: [
                claimingToken2,
                claimManagerAddress2
            ],
        });
    }

    

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });