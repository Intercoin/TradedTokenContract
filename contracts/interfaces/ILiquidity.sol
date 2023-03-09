// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILiquidity {
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external;
    function addLiquidity(uint256 tradedTokenAmount) external;
}
