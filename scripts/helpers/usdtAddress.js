
const hre = require('hardhat');

const getUSDTAddress = () => {
    const networkName = hre.network.name;
	const chainId = hre.network.config.chainId;

	//see https://cryptorank.io/price/tether
	if ((networkName == 'bsc') && (chainId == 56)) {
		return "0x55d398326f99059ff775485246999027b3197955";
	} else if ((networkName == 'polygonMumbai') && (chainId == 80001)) {
		return "0x9fb83c0635de2e815fd1c21b3a292277540c2e8d"; ///!!!!####
	} else if ((networkName == 'polygon') && (chainId == 137)) {
		return "0xc2132d05d31c914a87c6611c10748aeb04b58e8f";
	} else if ((networkName == 'mainnet') && (chainId == 1)) {
		return "0xdAC17F958D2ee523a2206206994597C13D831ec7";
	} else if ((networkName == 'hardhat')) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53"; //!!!!####
	} else {

		throw "unknown network for grab busd token | networkName=`"+networkName+"`; chainId=`"+chainId+"`";
	}
}

module.exports = { getUSDTAddress }
