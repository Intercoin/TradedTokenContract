// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

//import "hardhat/console.sol";


import "./minimums/libs/MinimumsLib.sol";


contract ITRv2 is Ownable, ERC777, IERC777Recipient {
    using MinimumsLib for MinimumsLib.UserStruct;
    

    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint64 internal constant LOCKUP_INTERVAL = 24*60*60; // day in seconds

    uint64 internal lockupIntervalAmount;
	//uint256 internal constant FRACTION = 100000;
    
    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    constructor(
        string memory name,
        string memory symbol,
        uint64 lockupDuration
    ) ERC777(name, symbol, new address[](0)) {

        lockupIntervalAmount = lockupDuration;
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
    @dev   … mints to caller
    */
    function claim(
        address account,
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        _mint(account, tradedTokenAmount, "", "");
        if (account != owner()) {
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupIntervalAmount, LOCKUP_INTERVAL, true);
        }
    }



    // ////////////////////////////////////////////////////////////////////////
    // // internal section ////////////////////////////////////////////////////
    // ////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256 amount
    ) 
        internal 
        virtual 
        override 
    {
        if (from !=address(0)) { // otherwise minted
            if (from == address(this) && to == address(0)) { // burnt by contract itself

            } else { 
                uint256 balance = balanceOf(from);
                uint256 locked = tokensLocked[from]._getMinimum();

                require(balance - locked >= amount, "insufficient amount");

            }
        }
    }    
    
    
    

   
    
    
   


}