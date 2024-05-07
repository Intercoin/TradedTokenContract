// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "./ERC777Mintable.sol";
import "../interfaces/ITradedToken.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";

/**
Imitation part of TradedToken contract: ERC777 and ITradedToken with minting tokens.
There are no uniswap, lock logic, transfer validation, bu/sell logic and other
*/
contract TradedTokenImitation is ERC777Mintable, ITradedToken, IERC777Recipient, IERC777Sender {

    uint256 internal availableToClaimVar;

    constructor () ERC777Mintable () {
        // register interfaces
        _ERC1820_REGISTRY.setInterfaceImplementer(address(this), keccak256("ERC777Token"), address(this));
       
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

    function availableToClaim() external view returns(uint256) { 
        return availableToClaimVar;
    }

    function claim(uint256 tradedTokenAmount, address account) external {
        if (availableToClaimVar == 0) {
            return;
        }
        _mint(account, tradedTokenAmount, "", "");
    }

    function setAvailableToClaim(uint256 amount) public {
        availableToClaimVar = amount;
    }
}
