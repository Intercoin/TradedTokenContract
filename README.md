# TradedTokenContract
A straightforward token contract for early investors to gradually begin selling on public exchanges

## About version 2
TradedTokenContract (Main.sol) is a ERC777 token with a couple improvements. 
<br>
After deploy contract creates a Uniswap(QuickSwap,PancakeSwap,etc) pair, owner should add initial liquidity and after that provide users to buy or sell this ERC77 token on platform.
main fetures are:
a. owner can provide additional liquidity in any time. Price in this case grow down, --------
b. owner can claim more erc777 tokens, but current price can not be drop less than minClaimPrice

