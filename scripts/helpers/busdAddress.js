
const hre = require('hardhat');

const getBUSDAddress = () => {
    const networkName = hre.network.name;
	const chainId = hre.network.config.chainId;

	//see https://cryptorank.io/price/binance-usd
	if (['bsc', 'localhost'].includes(networkName) && (chainId == 56)) {
		return "0xe9e7cea3dedca5984780bafc599bd69add087d56";
	} else if (['polygonMumbai', 'localhost'].includes(networkName) && (chainId == 80001)) {
		return "0x9fb83c0635de2e815fd1c21b3a292277540c2e8d";
	} else if (['polygon', 'localhost'].includes(networkName) && (chainId == 137)) {
		return "0x9C9e5fD8bbc25984B178FdCE6117Defa39d2db39";
	} else if (['mainnet', 'localhost'].includes(networkName) && (chainId == 1)) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53";
	} else if ((networkName == 'hardhat')) {
		return "0x4Fabb145d64652a948d72533023f6E7A623C7C53"; // use
	} else {

		throw "unknown network for grab busd token | networkName=`"+networkName+"`; chainId=`"+chainId+"`";
	}
}

module.exports = { getBUSDAddress }
