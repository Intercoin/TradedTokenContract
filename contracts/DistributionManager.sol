// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
//import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

import "./interfaces/ITokenExchange.sol";
import "./interfaces/IClaim.sol";

/**
* @title DistributionManager 
* will use in chain DistributionManager -> ClaimManager -> TradedToken
*/
contract DistributionManager is Ownable, IERC777Recipient, IERC777Sender, ReentrancyGuard {

    address public claimingToken;
    address public tradedToken;
    address public claimManager;

    IERC1820Registry internal constant _ERC1820_REGISTRY = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
    bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

    constructor(address claiming, address manager) {
        claimingToken = claiming;
        claimManager = manager;
        tradedToken = IClaim(claimManager).getTradedToken();
        IERC20(claimingToken).approve(manager, type(uint256).max);

        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_SENDER_INTERFACE_HASH, address(this));
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), _TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
    }

    function transfer(address account, uint256 amount) public onlyOwner {
        IERC20(tradedToken).transfer(account, amount);
    }
    
    function wantToClaim(uint256 amount) public onlyOwner {
        IClaim(claimManager).wantToClaim(amount);
    }

    function claim(uint256 amount, address account) public onlyOwner {
        IClaim(claimManager).claim(amount, account); // receive refund on unused ClaimingToken
    }

    function pauseBuy(bool status) public onlyOwner {
        ITokenExchange(tradedToken).pauseBuy(status);
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
