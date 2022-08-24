# TradedTokenContract
A straightforward token contract for early investors to gradually begin selling on public exchanges

## About version 2
TradedTokenContract (Main.sol) is a ERC777 token with a couple improvements. 
<br>
After deploy contract creates a Uniswap(QuickSwap,PancakeSwap,etc) pair, owner should add initial liquidity and after that provide users to buy or sell this ERC77 token on platform.<br>
The list of main features:<br>
<b>a.</b> owner(and managers) can provide additional liquidity in any time. Price in this case grow down, but can't drop less then average price multiple by `priceDrop_`<br>
<b>b.</b> owner(and managers) can claim more erc777 tokens, but current price can not be drop less than minClaimPrice<br>
<b>c.</b> anyone can claim erc777 tokens instead own external tokens(if `externalToken_` set up in constructor) but:<br>
&nbsp;&nbsp;&nbsp;&nbsp;- current price still can not be drop less than `minClaimPrice`<br>
&nbsp;&nbsp;&nbsp;&nbsp;- exchange rate will applicable by `externalTokenExchangePrice`<br>
<b>d.</b> any tokens transfer(except claim or burn) will locked up for a `lockupIntervalAmount_` days <br>
<b>e.</b> any buy/sell operations on uniswap will cut tokens by sell/buy taxes<br>
<b>f.</b> owner(and managers) can add any person to managers role, but can't remove from it<br>

