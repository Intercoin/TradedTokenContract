
const hre = require('hardhat');

const chainIDToNetworkName = (chainId) => {
   const id = Number(chainId);

	if (!Number.isInteger(id)) {
		throw `invalid chainId | value=\`${chainId}\``;
	}

	const map = {
		1: "mainnet",
		56: "bsc",
		137: "polygon",
		80001: "polygonMumbai"
	};

	const network = map[id];

	if (!network) {
		throw `unknown network | chainId=\`${chainId}\``;
	}

	return network;
}

module.exports = { chainIDToNetworkName }
