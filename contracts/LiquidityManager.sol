// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "./interfaces/ILiquidity.sol";

//import "hardhat/console.sol";

contract LiquidityManager is ILiquidity, IERC777Recipient, IERC777Sender, ReentrancyGuard {

    address public immutable tradedToken;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    error EmptyTokenAddress();
    
    constructor (
        address tradedToken_    
    ) {
        tradedToken = tradedToken_;

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    /**
     * @dev adding initial liquidity. need to donate `amountReserveToken` of reserveToken into the contract. can be called once
     * @param amountTradedToken amount of traded token which will be claimed into contract and adding as liquidity
     * @param amountReserveToken amount of reserve token which must be donate into contract by user and adding as liquidity
     */
    function addInitialLiquidity(uint256 amountTradedToken, uint256 amountReserveToken) nonReentrant external {
        ILiquidity(tradedToken).addInitialLiquidity(amountTradedToken, amountReserveToken);
    }

    /**
     * @dev claims, sells, adds liquidity, sends LP to 0x0
     * @custom:calledby owner
     */
    function addLiquidity(uint256 tradedTokenAmount) nonReentrant external {
        ILiquidity(tradedToken).addLiquidity(tradedTokenAmount);
    }

      /**
     * @notice part of IERC777Recipient
     */
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

    /**
     * @notice part of IERC777Sender
     */
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external {}

}
