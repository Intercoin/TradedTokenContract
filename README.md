# TradedTokenContract
A straightforward token contract for early investors to gradually begin selling on public exchanges

## Technology

The original goal of Bitcoin and other cryptocurrencies was to eliminate the need for participants to trust a centralized third party. It worked because the software was distributed to a large ecosystem of nodes and miners. No one worried about the Litecoin or Ripple network "rugpulling" them.

But in the last few years, many projects released their own tokens, by hiring devs that ended up cloning some smart contract they found on the internet. Usually it was a smart contract of a famous project, like SafeMoon or EverRise. However, many of those contracts ended up having **[bugs](https://community.intercoin.app/t/safemoon-upgrade-has-a-fatal-bug-public-burn-function/2778)**, or intentional **[scams and honeypots](https://www.youtube.com/watch?v=bs_-tu9qgM8)**. Other times, the team simply **[rug-pulled](https://www.bankrate.com/investing/what-is-a-rug-pull/)** liquidity from the exchange. The Web3 token ecosystem is largely broken. Token holders started to verbalize **[learned helplessness](https://en.wikipedia.org/wiki/Learned_helplessness)**, saying it's just the "wild west". But it doesn't have to be!

Intercoin spent the last 5 years building **[smart contract factories](https://community.intercoin.app/t/intercoin-smart-contract-security/2759)** to restore confidence in the Web3 token ecosystem. Using Intercoin's technology, projects can produce their tokens on-chain from a carefully developed and audited factory, thus ensuring they all have identical code. Tokens powered by Intercoin benefit from day 1 from having been officially audited and endorsed by companies like CertiK:

**https://www.certik.com/projects/intercoin**

Think of how UniSwap's factory, for instance, produces liquidity pools. People have confidence in the UniSwap ecosystem precisely because each instance has identical code, and only differs in a limited set of parameters that were selected when it was produced. These parameters are described below.

## Features

**[Power your next token with Intercoin smart contracts!](https://community.intercoin.app/t/power-your-next-token-with-intercoins-smart-contracts/2832)**

Intercoin's TradedTokenContract has been carefully designed, from the bottom up, to give its holders massive confidence. Unlike most tokens out there, it can guarantee things like:

💧 **Auto-Liquidity**: Project managers don't have to worry about adding too much or too little liquidity to the trading pool. As more people buy the token, it can automatically mint small amounts of itself, to swap and grow both sides of the liquidity pool. **[This helps reduce slippage for holders,](https://redefine.net/media/uniswap/)** without requiring liquidity providers to expose themselves to risk of impermanent loss

🔒 **Locked Liquidity**: All the auto-liquidity that's added to the pool is locked there permanently, because the token contract sends the LP tokens to the zero address. Thus, any participant can easily verify on-chain that all those LP tokens can truly never be recovered. This is in contrast to other projects that fake "liquidity locking" by sending LP tokens to some contract address, which may turn out to be recoverable after all. **[This helps protect holders from rugpulls.](https://cointelegraph.com/explained/crypto-rug-pulls-what-is-a-rug-pull-in-crypto-and-6-ways-to-spot-it)**

😱 **Anti-Panic**: When deploying the token contract, the project team can choose to limit the rate at which people can sell to, say, 5% per day (configurable parameter). This means panic sell-offs can be slowed down, to take place over multiple days, and during that time, new buyers can appear, or the team can try to stabilize whatever external situation is causing the panic. **[This helps protect the crowd from each other's herd mentality](https://www.washingtonpost.com/wellness/2022/10/31/seoul-crowd-crush-how-to-survive/)**.

🚰 **Anti-Dilution**: Insiders, such as the team and presale investors, are limited in how much of the token they can mint to themselves. The system is designed to guarantee that if all those tokens were sold, the price would only drop from the all-time-high by, say, 10% (configurable parameter). Our **[ClaimManager contract](https://github.com/Intercoin/TradedTokenContract/blob/main/contracts/ClaimManager.sol)** helps insiders fairly distribute the tokens available to them from time to time. **[This helps protect holders from massive monetary inflation in the token.](https://learn.bybit.com/crypto/inflationary-vs-deflationary-cryptocurrency/)**

🙌 **Trade In Old Token**: If you have a previous token that you issued, even if it's on another chain, we can help you set up a system to let people gradually bridge and swap over into the new token at a certain rate (configurable parameter). All the Anti-Dilution rules described above still apply, but in addition, the people have to hold the old token. **[This helps give a way for holders of the old token to gradually migrate over into your new, more secure, ecosystem.](https://mantraomniverse.medium.com/om-token-v2-migration-step-by-step-guide-e26e04196d29)**

🎁 **Presale Support**: The token contract supports designating other smart contracts to conduct pre-sales, before liquidity is added to the Uniswap trading pool. For this purpose, we recommend using Intercoin's **[FundContract](https://github.com/Intercoin/FundContract)**, which has features such whitelists, prices, tranches, and even group discounts! Together, our smart contracts can give holders confidence that no one got the token without buying it for a specific floor price. **[This helps protect people from dumping by those who may have received it via an airdrop or in exchange for some off-chain arrangements.](https://ontropy.substack.com/p/why-99-of-airdrops-dump)**

🛒 **Buy and Sell Taxes**: Intercoin's token contract also supports setting a tax rate for buying, and a separate rate for selling (configurable parameters). The taxes can even be set to increase or decrease gradually over a period, such as a year, so people know exactly what to expect. Tokens collected via taxes are immediately burned, **[which can be used to balance the minting to insiders and for auto-liquidity, or even to make the token hyper-deflationary!](https://www.yahoo.com/video/deflationary-tokens-empower-crypto-project-153845806.html)**

## Claiming
The diagram below shows how TradedTokens can be claimed

```mermaid
stateDiagram-v2

[*] --> claim
[*] --> сlaimViaExternal

    state claim {
        onlyOwnerAndManagers
    }
    state сlaimViaExternal {
      сlaimViaExternalValidate1: check allowance, ClaimFrequency
      сlaimViaExternalSafeTransferFrom: transfer to DEAD Address
      сlaimViaExternalConvert: convert via claimingTokenExchangePrice
      
        сlaimViaExternalValidate1 --> approve
        approve --> сlaimViaExternalSafeTransferFrom
        сlaimViaExternalSafeTransferFrom --> сlaimViaExternalConvert
        сlaimViaExternalConvert --> scaling
    }
    state ValidateClaim {
        ValidateClaim1: Price can not be drop more than minClaimPrice
    }
claim --> ValidateClaim
сlaimViaExternal --> ValidateClaim
ValidateClaim --> MintTokens
MintTokens --> [*]
```
