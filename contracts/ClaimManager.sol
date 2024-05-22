// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ClaimBase.sol";

/**
* @title ClaimManager 
* will use as a manager for TradedToken to claim tokens. Chain will be like this ClaimManager -> TradedToken
*/
contract ClaimManager is ClaimBase, IERC777Recipient, IERC777Sender, ReentrancyGuard {
    using SafeERC20 for ERC777;

    constructor (
        address tradedToken_,
        ClaimSettings memory claimSettings
        
    ) {
        __ClaimBaseInit(tradedToken_, claimSettings);
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

    function claim(uint256 claimingTokenAmount, address account) external nonReentrant() {
        _claim(claimingTokenAmount, account);
    }

    function wantToClaim(uint256 amount) external {
        _wantToClaim(amount);
    }
    
    function claimingTokenAllowance(address from, address to) internal override view returns(uint256) {
        return ERC777(claimingToken).allowance(from, to);
    }

    function getClaimingTokenBalanceOf(address account) internal override view returns(uint256) {
        return ERC777(claimingToken).balanceOf(account);
    }

    function claimingTokenTransferFrom(address from, address to, uint256 claimingTokenAmount) internal override {
        ERC777(claimingToken).safeTransferFrom(from, to, claimingTokenAmount);
    }

}

