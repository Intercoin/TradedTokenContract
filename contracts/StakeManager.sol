// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./StakeBase.sol";

//import "hardhat/console.sol";

contract StakeManager is StakeBase, IERC777Recipient, IERC777Sender, ReentrancyGuard {
    using SafeERC20 for ERC777;

    constructor (
        address tradedToken_,
        address stakingToken_,
        uint16 bonusSharesRate_,
        uint16 defaultStakeDuration_
        
    ) {
        __StakeBaseInit(tradedToken_, stakingToken_, bonusSharesRate_, defaultStakeDuration_);
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
    ) external {
        _stakeFromAddress(from, amount, defaultStakeDuration);
    }

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

    function _transfer(address token, address to, uint256 amount) internal {
        ERC777(token).transfer(to, amount);
    }
    function _transferFrom(address token, address sender, uint256 amount) internal {
        ERC777(token).transferFrom(sender, amount);
    }
}

