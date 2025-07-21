const fs = require('fs');
const hre = require('hardhat');

const { isAddress } = require('ethers');

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

    const argPath = process.env.argPath?.trim();

	const { 
		getArguments
	} = require(argPath);

    const args = getArguments();

    const mode              = args.mode?.trim().toLowerCase();
    var presaleAddress      = args.presaleAddress?.trim().toLowerCase();
    const amount            = args.amount?.trim().toLowerCase();
    const days              = args.days?.trim().toLowerCase();
    const ownerPrivateKey   = args.ownerPrivateKey?.trim().toLowerCase();

    const networkName = hre.network.name;
    var signers = await hre.ethers.getSigners();

    var deployer, tradedTokenAddress;

    switch (mode) {
    case 'itr':
        if (signers.length == 1) {
            deployer = signers[0];
        } else {
            [
            ,//deployer,
            ,//deployer_auxiliary,
            ,//deployer_releasemanager,
            ,//deployer_inter,
            ,//deployer_qbux,
            ,//deployer_claim,
            ,//deployer_stake,
            ,//deployer_claiming_token_itr,
            ,//deployer_claiming_token_qbix,
            deployer,//deployer_itr,
            ,//deployer_qbix
            ] = signers;
        }
        tradedTokenAddress = '0x1117d11930a11d2e36eff79e47ac92d25551b155';

        break;
    case 'qbix':
        if (signers.length == 1) {
            deployer = signers[0];
        } else {
            [
            ,//deployer,
            ,//deployer_auxiliary,
            ,//deployer_releasemanager,
            ,//deployer_inter,
            ,//deployer_qbux,
            ,//deployer_claim,
            ,//deployer_stake,
            ,//deployer_claiming_token_itr,
            ,//deployer_claiming_token_qbix,
            ,//deployer_itr,
            deployer,//deployer_qbix
            ] = signers;

            tradedTokenAddress = '0xfaced1a6dc5d064ba397cb9be8c6cd666b8ddabb';
        }
        break;
    default:
        throw(`mode '${mode}' unsupported`);      
    }

    
    if (
        typeof presaleAddress === 'undefined' ||
        typeof amount === 'undefined' ||
        typeof days === 'undefined' ||
        !presaleAddress ||
        !isAddress(presaleAddress) ||
        !amount ||
        !days
    ) {
        throw("Arguments file: wrong parameters");
    }
    
    var pathLib;
    if (networkName == 'hardhat') {
        pathLib = '../libraries/bsc/list.js';
    } else {
        pathLib = '../libraries/'+networkName+'/list.js';
    }
    const libs = require(pathLib);

    const itrF = await hre.ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});
  
    const itr = itrF.attach(tradedTokenAddress);
    var tx;

    
    var deployerOverrode;
    // override deployer if private key present
    if (typeof ownerPrivateKey !== 'undefined') {
        console.log(ownerPrivateKey);
        var deployerOverrode = new hre.ethers.Wallet(ownerPrivateKey, hre.ethers.provider); 
        
        if (networkName == 'hardhat') {
            console.log("networkName == 'hardhat'");
            // get owner
            console.log("get real owner");
            var itrOwnerAddress = await itr.connect(deployer).owner();
            if (itrOwnerAddress != deployerOverrode.address) {
                console.log("impersonate");
                await hre.network.provider.request({
                    method: "hardhat_impersonateAccount",
                    params: [itrOwnerAddress],
                });
                console.log("setBalance");
                await hre.network.provider.send("hardhat_setBalance", [
                    itrOwnerAddress,
                    "0x1000000000000000000" // 1 ETH
                ]);
                await hre.network.provider.send("hardhat_setBalance", [
                    deployerOverrode.address,
                    "0x1000000000000000000" // 1 ETH
                ]);

                const itrOwner = await hre.ethers.getSigner(itrOwnerAddress);
                console.log("transferOwnership");
                await itr.connect(itrOwner).transferOwnership(deployerOverrode.address);

                // override presale address
                const PresaleMockF = await hre.ethers.getContractFactory("PresaleMock");
                console.log("override presale");
	            var PresaleMock = await PresaleMockF.connect(deployerOverrode).deploy();
                await PresaleMock.connect(deployerOverrode).setEndTime(999999999);
                presaleAddress = PresaleMock.target;

            }
        }
        deployer = deployerOverrode;
    }

    console.log("deployer address", deployer.address);
    console.log("Account balance:", (await hre.ethers.provider.getBalance(deployer.address)).toString());
	
    //startPresale(address contract_, uint256 amount, uint64 presaleLockupDays) public onlyOwner {
    tx = await itr.connect(deployer).startPresale(presaleAddress, amount, days);
    // and wait the last one
    await tx.wait(); // 0ms, as tx is already confirmed

    console.log("done. Check manually if need");
    return;

}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });