
const hre = require('hardhat');

const getUSDCAddress = () => {
    const networkName = hre.network.name;
	const chainId = hre.network.config.chainId;
	
    // https://coinmarketcap.com/currencies/usd-coin/
    if ((networkName == 'bsc') && (chainId == 56)) {
		return "0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d";
    } else if ((networkName == 'polygon') && (chainId == 137)) {
		return "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359";
	} else if ((networkName == 'mainnet') && (chainId == 1)) {
		return "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
	} else if ((networkName == 'optimism') && (chainId == 10)) {
		return "0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85";
	} else if ((networkName == 'base') && (chainId == 8453)) {
		return "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
	} else if ((networkName == 'hardhat')) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53"; //!!!!####
	} else {
		throw "unknown network for grab usdc token | networkName=`"+networkName+"`; chainId=`"+chainId+"`";
	}
}

module.exports = { getUSDCAddress }
