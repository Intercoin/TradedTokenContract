// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ITradedToken.sol";

interface ITradedTokenUpgradeable is ITradedToken {
    
    /**
     * @param tokenName token name
     * @param tokenSymbol token symbol
     * @param reserveToken reserve token address
     * @param priceDrop price drop while add liquidity
     * @param lockupDays interval amount in days (see minimum lib)
     * @param claimSettings struct of claim settings
     * @param claimSettings.minClaimPrice (numerator,denominator) minimum claim price that should be after "sell all claimed tokens"
     * @param claimSettings.minClaimPriceGrow (numerator,denominator) minimum claim price grow
     * @param taxes_.buyTaxMax buyTaxMax
     * @param taxes_.sellTaxMax sellTaxMax
     * @param taxes_.holdersMax the maximum number of holders, may be increased by owner later
     */
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        address reserveToken, //” (USDC)
        uint256 priceDrop,
        uint64 lockupDays,
        ClaimSettings memory claimSettings,
        TaxesLib.TaxesInfoInit memory taxesInfoInit,
        Taxes memory taxes_,
        address costManager,
        address producedBy
    ) external;

}

