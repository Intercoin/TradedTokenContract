// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

//import "hardhat/console.sol";

contract Liquidity is IERC777Recipient {

    address internal immutable token0;
    address internal immutable token1;
    address internal immutable uniswapRouter;
    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    constructor(
        address token0_,
        address token1_,
        address uniswapRouter_
    ) {
        token0 = token0_;
        token1 = token1_;
        uniswapRouter = uniswapRouter_;

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        
    }

    /**
    * adding liquidity for all available balance
    */
    function addLiquidity(
    )
        external 
    {
        uint256 token0Amount = IERC20(token0).balanceOf(address(this));
        uint256 token1Amount = IERC20(token1).balanceOf(address(this));

        _addLiquidity(token0Amount, token1Amount);
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {
       
    }

    /**
    * approve tokens to uniswap router obtain LP tokens and move to zero address
    */
    function _addLiquidity(
        uint256 token0Amount,
        uint256 token1Amount
    )
        internal
    {
        IERC20(token0).approve(address(uniswapRouter), token0Amount);
        IERC20(token1).approve(address(uniswapRouter), token1Amount);

         //(/* uint256 A*/, /*uint256 B*/, /*uint256 lpTokens*/) = 
         IUniswapV2Router02(uniswapRouter).addLiquidity(
            token0,
            token1,
            token0Amount,
            token1Amount,
            0, // there may be some slippage
            0, // there may be some slippage
            address(0), 
            block.timestamp
        );
    }
}