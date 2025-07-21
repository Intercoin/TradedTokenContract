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

async function main() {
  
  const mode = process.env.mode?.trim().toLowerCase();
  const tradedTokenAddress = process.env.tradedtoken?.trim().toLowerCase();
  const networkName = hre.network.name;

  console.log("Mode:", mode);
  console.log("tradedTokenAddress: ", tradedTokenAddress);
  console.log("hre.network.name: ", networkName);

  var data = await get_data();
  var data_object_root = JSON.parse(data);
	if (typeof data_object_root[networkName] === 'undefined') {
		throw("Arguments file: missed data");
  } else if (typeof data_object_root[networkName] === 'undefined') {
		throw("Arguments file: missed network data");
  }

  var signers = await ethers.getSigners();

  var deployer;
  var managersToAdd = [];

  if (networkName == 'hardhat') {
    data_object = data_object_root['bsc'];
  } else {
    data_object = data_object_root[networkName];
  }
	//data_object = data_object_root[networkName];

  switch (mode) {
    case 'itr':
      if (
        typeof data_object.claimingManagerITR === 'undefined' ||
        typeof data_object.liquidityManagerITR === 'undefined' ||
        !data_object.claimingManagerITR ||
        !data_object.liquidityManagerITR
      ) {
        throw("Arguments file: wrong addresses");
      }
      managersToAdd.push(data_object.claimingManagerITR);
      managersToAdd.push(data_object.liquidityManagerITR);
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
      
      break;
    case 'qbix':
      if (
          typeof data_object.claimingManagerQBIX === 'undefined' ||
          typeof data_object.distributionManagerQBIX === 'undefined' ||
          typeof data_object.liquidityManagerQBIX === 'undefined' ||
          !data_object.claimingManagerQBIX ||
          !data_object.distributionManagerQBIX ||
          !data_object.liquidityManagerQBIX
        ) {
          throw("Arguments file: wrong addresses");
        }
        managersToAdd.push(data_object.claimingManagerQBIX);
        managersToAdd.push(data_object.distributionManagerQBIX);
        managersToAdd.push(data_object.liquidityManagerQBIX);
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
      }
      break;
    default:
      throw(`mode '${mode}' unsupported`);      
  }
	console.log("managersToAdd", managersToAdd);
  console.log("deployer address", deployer.address);

  console.log("Account balance:", (await ethers.provider.getBalance(deployer.address)).toString());

  var pathLib;
  if (networkName == 'hardhat') {
    pathLib = '../libraries/bsc/list.js';
  } else {
    pathLib = '../libraries/'+networkName+'/list.js';
  }
  const libs = require(pathLib);
  //const libs = require('../libraries/'+networkName+'/list.js');

  const itrF = await ethers.getContractFactory("TradedToken",  {
		libraries: {
			TaxesLib:libs.TaxesLib
		}
	});
  
  const itr = itrF.attach(tradedTokenAddress);
  var tx;
  for (var i in managersToAdd) {
    console.log(managersToAdd[i]);
    tx = await itr.connect(deployer).addManager(managersToAdd[i]);
  }
  // and wait the last one
  await tx.wait(3); // 0ms, as tx is already confirmed

  console.log("done. Check manually if need");
return;

   //--myParam=hello
// ClaimManager
// LiquidityManager
// DistrubutionManager
/*    
const list = [

        "0x503856471c9D905D71aF07E997d1723b1f34D46b",
        "0xA5b81AD44e8C1C9F9937C7b94AD573Bd6c659bD6",
        "0x255dfFb6763bcB0261dB009181bDd0E911D13818",
        "0xBA7228A4Cd158B2Ea2fb3AC89e8b4c9F21c8b74b",
        "0x7Cf85bA94fd2C80c5d7A41F220412A270d1e7538",
        "0xD029B9a4489F44A4cFB48361A8320058056b6A30",
        "0x36c3002fe7d559809B96dA4dd8D78328e519DDbA"
    ];
    for (var i in list) {
        console.log(list[i]);
    }
        */
}

main()
  .then(() => process.exit(0))
  .catch(error => {
	console.error(error);
	process.exit(1);
  });