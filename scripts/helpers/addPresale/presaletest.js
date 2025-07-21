function getArguments(){
    return {
        mode: 'itr',
        // as example - put here any valid address. in script we are trying to dynamically created valid contract PresaleMock instead of this
        presaleAddress: '0x1117d11930a11d2e36eff79e47ac92d25551b155', 
        amount: '1000000000000000000',
        days: '0',
        // https://hardhat.org/hardhat-network/docs/overview
        // Account #0: 0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266 (10000 ETH)
        // Private Key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
        ownerPrivateKey: '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80'
    };
}
module.exports = {
    getArguments
}