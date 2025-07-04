require('dotenv').config();
require("@nomicfoundation/hardhat-toolbox");
require("hardhat-contract-sizer");

const kovanURL = `https://eth-kovan.alchemyapi.io/v2/${process.env.ALCHEMY_KOVAN}`
const goerliURL = `https://eth-goerli.alchemyapi.io/v2/${process.env.ALCHEMY_GOERLI}`
const rinkebyURL = /*`https://rinkeby.infura.io/v3/${process.env.INFURA_ID_PROJECT}` */`https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_RINKEBY}`
const bscURL = 'https://bsc-dataseed.binance.org' //`https://eth-rinkeby.alchemyapi.io/v2/${process.env.ALCHEMY_RINKEBY}`
const bsctestURL = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const mainnetURL = `https://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_MAINNET}`
const maticURL = `https://polygon-mainnet.g.alchemy.com/v2/${process.env.ALCHEMY_MATIC}`
const mumbaiURL = `https://matic-mumbai.chainstacklabs.com`;
const baseURL = 'https://mainnet.base.org';
const optimismURL = 'https://optimism.llamarpc.com';

module.exports = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      allowUnlimitedContractSize: true,
      // bsc
      // chainId: 0x38,  // sync with url or getting uniswap settings will reject transactions
      // forking: {url: bscURL}
      // matic
      chainId: 137,  // sync with url or getting uniswap settings will reject transactions
      forking: {url: maticURL}
      // mainnet
      // chainId: 1,  // sync with url or getting uniswap settings will reject transactions
      // forking: {url: mainnetURL}

    },
    kovan: {
      url: kovanURL,
      chainId: 42,
      gas: 12000000,
      accounts: [process.env.private_key],
      saveDeployments: true
    },
    goerli: {
      url: goerliURL,
      chainId: 5,
      gasPrice: 1000,
      accounts: [process.env.private_key],
      saveDeployments: true
    },
    rinkeby: {
      url: rinkebyURL,
      chainId: 4,
      gasPrice: "auto",
      accounts: [process.env.private_key],
      saveDeployments: true
    },
    bsc: {
      url: bscURL,
      chainId: 56,
      //gasPrice: "auto",
      //accounts: [process.env.private_key],
      accounts: [
        process.env.private_key,
        process.env.private_key_auxiliary,
        process.env.private_key_releasemanager,
        process.env.private_key_tradedTokenINTER,
        process.env.private_key_tradedTokenQBUX,
        process.env.private_key_claim,
        process.env.private_key_stake,
        process.env.private_key_claimingTokenITR,
        process.env.private_key_claimingTokenQBIX,
        process.env.private_key_tradedTokenITR,
        process.env.private_key_tradedTokenQBIX
      ],
      saveDeployments: true
    },
    bsctest: {
      url: bsctestURL,
      chainId: 97,
      gasPrice: "auto",
      accounts: [process.env.private_key],
      saveDeployments: true
    },
    polygon: {
      url: maticURL,
      chainId: 137,
      //gasPrice: 20_000000000,
      //accounts: [process.env.private_key],
      accounts: [
        process.env.private_key,
        process.env.private_key_auxiliary,
        process.env.private_key_releasemanager,
        process.env.private_key_tradedTokenINTER,
        process.env.private_key_tradedTokenQBUX,
        process.env.private_key_claim,
        process.env.private_key_stake,
        process.env.private_key_claimingTokenITR,
        process.env.private_key_claimingTokenQBIX,
        process.env.private_key_tradedTokenITR,
        process.env.private_key_tradedTokenQBIX
      ],
      saveDeployments: true
    },
    polygonMumbai: { // matic test
      url: mumbaiURL,
      chainId: 80001,
      gasPrice: "auto",
      //accounts: [process.env.private_key],
      accounts: [process.env.private_key_auxiliary],
      saveDeployments: true
    },
    mainnet: {
      url: mainnetURL,
      chainId: 1,
      //gasPrice: 20000000000,
      //accounts: [process.env.private_key],
      accounts: [
        process.env.private_key,
        process.env.private_key_auxiliary,
        process.env.private_key_releasemanager,
        process.env.private_key_tradedTokenINTER,
        process.env.private_key_tradedTokenQBUX,
        process.env.private_key_claim,
        process.env.private_key_stake,
        process.env.private_key_claimingTokenITR,
        process.env.private_key_claimingTokenQBIX,
        process.env.private_key_tradedTokenITR,
        process.env.private_key_tradedTokenQBIX
      ],
      saveDeployments: true
    },
    base: {
      url: baseURL,
      chainId: 8453,
      accounts: [
        process.env.private_key,
        process.env.private_key_auxiliary,
        process.env.private_key_releasemanager,
        process.env.private_key_tradedTokenINTER,
        process.env.private_key_tradedTokenQBUX,
        process.env.private_key_claim,
        process.env.private_key_stake,
        process.env.private_key_claimingTokenITR,
        process.env.private_key_claimingTokenQBIX,
        process.env.private_key_tradedTokenITR,
        process.env.private_key_tradedTokenQBIX
      ],
      saveDeployments: true
    },
    optimisticEthereum: {
      url: optimismURL,
      chainId: 10,
      accounts: [
        process.env.private_key,
        process.env.private_key_auxiliary,
        process.env.private_key_releasemanager,
        process.env.private_key_tradedTokenINTER,
        process.env.private_key_tradedTokenQBUX,
        process.env.private_key_claim,
        process.env.private_key_stake,
        process.env.private_key_claimingTokenITR,
        process.env.private_key_claimingTokenQBIX,
        process.env.private_key_tradedTokenITR,
        process.env.private_key_tradedTokenQBIX
      ],
      saveDeployments: true
    }
  },
  gasReporter: {
    enabled: process.env.REPORT_GAS !== undefined,
    currency: "USD"
  },
  etherscan: {
    //apiKey: process.env.MATIC_API_KEY  
    //apiKey: process.env.ETHERSCAN_API_KEY
    //apiKey: process.env.BSCSCAN_API_KEY
    apiKey: {
      polygon: process.env.MATIC_API_KEY,
      polygonMumbai: process.env.MATIC_API_KEY,
      mainnet: process.env.ETHERSCAN_API_KEY,
      bsctest: process.env.BSCSCAN_API_KEY,
      bsc: process.env.BSCSCAN_API_KEY,
      optimisticEthereum: process.env.OPTIMISM_API_KEY,
      base: process.env.BASE_API_KEY    
    }
  },
  solidity: {
    compilers: [
        {
          version: "0.8.24",
          settings: {
            //viaIR: true,
            optimizer: {
              enabled: true,
              runs: 10,
            },
            metadata: {
              // do not include the metadata hash, since this is machine dependent
              // and we want all generated code to be deterministic
              // https://docs.soliditylang.org/en/v0.7.6/metadata.html
              bytecodeHash: "none",
            },
          },
        },
        {
          version: "0.8.15",
          settings: {
            //viaIR: true,
            optimizer: {
              enabled: true,
              runs: 10,
            },
            metadata: {
              // do not include the metadata hash, since this is machine dependent
              // and we want all generated code to be deterministic
              // https://docs.soliditylang.org/en/v0.7.6/metadata.html
              bytecodeHash: "none",
            },
          },
        },
        {
          version: "0.6.7",
          settings: {},
          settings: {
            //viaIR: true,
            optimizer: {
              enabled: false,
              runs: 200,
            },
            metadata: {
              // do not include the metadata hash, since this is machine dependent
              // and we want all generated code to be deterministic
              // https://docs.soliditylang.org/en/v0.7.6/metadata.html
              bytecodeHash: "none",
            },
          },
        },
      ],
  
    
  },

  namedAccounts: {
    deployer: 0,
    },

  paths: {
    sources: "contracts",
  },
  gasReporter: {
    currency: 'USD',
    enabled: (process.env.REPORT_GAS === "true") ? true : false
  },
  mocha: {
    timeout: 200000
  }
 
}
