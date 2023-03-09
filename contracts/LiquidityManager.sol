// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interfaces/ILiquidity.sol";

//import "hardhat/console.sol";

contract LiquidityManager is ILiquidity, IERC777Recipient, IERC777Sender, ReentrancyGuard {

    address public immutable tradedToken;
    
    error EmptyTokenAddress();
    
    constructor (
        address tradedToken_    
    ) {
        tradedToken = tradedToken_;
    }

    /**
     * @dev adding initial liquidity. need to donate `amountReserveToken` of reserveToken into the contract. can be called once
     * @param amountTradedToken amount of traded token which will be claimed into contract and adding as liquidity
     * @param amountReserveToken amount of reserve token which must be donate into contract by user and adding as liquidity
     */
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) external {
        ILiquidity(tradedToken).addInitialLiquidity(amountTradedToken, amountReserveToken);
    }

    /**
     * @dev claims, sells, adds liquidity, sends LP to 0x0
     * @custom:calledby owner
     */
    function addLiquidity(uint256 tradedTokenAmount) external {
        ILiquidity(tradedToken).addLiquidity(tradedTokenAmount);
    }
}
