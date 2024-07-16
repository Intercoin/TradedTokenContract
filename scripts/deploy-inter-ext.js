const fs = require('fs');
const hre = require('hardhat');
const paramArguments = require('./arguments-inter.js');

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
		deployer_itr.address
	);

	var options = {
		//gasPrice: ethers.utils.parseUnits('50', 'gwei'), 
		//gasLimit: 5e6
	};

	let params = [
		...paramArguments,
		options
	];

	console.log("Account balance:", (await ethers.provider.getBalance(deployer_itr.address)).toString());

    let tx,tx2;
    const claimManagerFactory = await ethers.getContractAt("ClaimManagerFactory", "0x130101007bA13B731669bdF23819924F3213f1B8");
    
    // StakingToken: ITR
    // TradedToken: INTER
    const claimingToken1 = "0x1111158f88410DA5F92c7E34c01e7B8649Bc0155"; // ITR(CERTIK)
    const tradedToken1 = "0x1111cCCBd70ff1eE6fa49BC411b75D16dC321111"; //INTER

    const claimingToken2 = "0x3333348558AF892D76a071Da58cD4288fE9b3333"; // QBIX(CERTIK)
    const tradedToken2 = "0x333333334Cf6335B755Afe59F4670bC766c93859"; //QBUX
    // StakingToken: ITR
    // TradedToken: INTER
    tx = await claimManagerFactory.connect(deployer_itr).produce(
        //address tradedToken,
        tradedToken1, 
        //IClaimUpgradeable.ClaimSettings memory claimSettings
        [
            claimingToken1, // ITR(CERTIK)
            [1,1],  // 1
            604800  //WEEK
        ]
    );

    // StakingToken: QBIX
    // TradedToken: QBUX
    tx2 = await claimManagerFactory.connect(deployer_itr).produce(
        //address tradedToken,
        tradedToken2, 
        //IClaimUpgradeable.ClaimSettings memory claimSettings
        [
            claimingToken2, // QBIX(CERTIK)
            [1,1],  // 1
            604800  //WEEK
        ]
    );

    await tx.wait();
    await tx2.wait();

    var rc, event,instance;
    rc = await tx.wait(); // 0ms, as tx is already confirmed
    event = rc.logs.find(event => event.fragment && event.fragment.name === 'InstanceCreated');
    [instance,] = event.args;
    const claimManagerAddress1 = instance;
    //-----
    rc = await tx2.wait(); // 0ms, as tx is already confirmed
    event = rc.logs.find(event => event.fragment && event.fragment.name === 'InstanceCreated');
    [instance,] = event.args;
    const claimManagerAddress2 = instance;
    //------------

    const distributionManagerF = await ethers.getContractFactory("distributionManager");
    await distributionManagerF.connect(deployer_itr).deploy(
        // address claiming, 
        claimingToken1,
        // address manager
        claimManagerAddress1
    );

    await distributionManagerF.connect(deployer_itr).deploy(
        // address claiming, 
        claimingToken2,
        // address manager
        claimManagerAddress2
    );

	const networkName = hre.network.name;
	
	const libs = require('./libraries/'+networkName+'/list.js');

	const MainF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});


	this.instance = await MainF.connect(deployer_itr).deploy(...params);

	await this.instance.waitForDeployment();
	
	console.log("Instance deployed at:", this.instance.target);
	console.log("with params:", [...paramArguments]);
	console.log("TaxesLib.library deployed at:", libs.TaxesLib);

	await hre.run("verify:verify", {
		address: this.instance.target,
		constructorArguments: paramArguments,
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });