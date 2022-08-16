// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "hardhat/console.sol";

import "./libs/SwapSettingsLib.sol";

import "./minimums/libs/MinimumsLib.sol";

import "./ExecuteManager.sol";

contract ITRv2 is Ownable, ERC777, AccessControl, IERC777Recipient, ExecuteManager {
    using MinimumsLib for MinimumsLib.UserStruct;
    

    address private constant deadAddress = 0x000000000000000000000000000000000000dEaD;
    uint64 internal constant LOCKUP_INTERVAL = 24*60*60; // day in seconds

    uint64 internal lockupIntervalAmount;
	//uint256 internal constant FRACTION = 100000;
    uint256 public totalCumulativeClaimed;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    address immutable uniswapRouter;
    // OWNER
    bytes32 internal constant OWNER_ROLE = 0x4f574e4552000000000000000000000000000000000000000000000000000000;

    constructor(
        string memory name,
        string memory symbol,
        uint64 lockupDuration
    ) 
        ERC777(name, symbol, new address[](0)) 
    {

        lockupIntervalAmount = lockupDuration;
        (uniswapRouter, /*uniswapRouterFactory*/) = SwapSettingsLib.netWorkSettings();
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
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
    @dev   … mints to account
    */
    function claim(
        address account,
        uint256 tradedTokenAmount
    ) 
        public 
        onlyOwner
    {
        totalCumulativeClaimed += tradedTokenAmount;

        _mint(account, tradedTokenAmount, "", "");
        if (
            account != owner() &&
            //to != uniswapRouter &&
            hasRole(OWNER_ROLE, account) == false
        ) {    
            tokensLocked[account]._minimumsAdd(tradedTokenAmount, lockupIntervalAmount, LOCKUP_INTERVAL, true);
        }
    }

    // function startupInit(
    //     address uniswapV2Pair,
    //     uint256 priceDrop, 
    //     uint64 averagePriceWindow,
    //     uint64 fraction
    // ) 
    //     external 
    //     onlyOwner
    //     runOnlyOnce
    // {
        
    // }

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

        // owner - contract main
        // real owner User
        // console.log("======================");
        // console.log("                                   address               [isAdmin] [isOwner]");
        // console.log("operator       = ", operator, hasRole(DEFAULT_ADMIN_ROLE,operator), hasRole(OWNER_ROLE,operator));
        // console.log("from           = ", from, hasRole(DEFAULT_ADMIN_ROLE,from), hasRole(OWNER_ROLE,from));
        // console.log("to             = ", to, hasRole(DEFAULT_ADMIN_ROLE,to), hasRole(OWNER_ROLE,to));
        // console.log("----------------------");
        // console.log("address(this)  = ", address(this), hasRole(DEFAULT_ADMIN_ROLE,address(this)), hasRole(OWNER_ROLE,address(this)));
        // console.log("owner()        = ", owner(), hasRole(DEFAULT_ADMIN_ROLE,owner()), hasRole(OWNER_ROLE,owner()));
        // console.log("uniswapRouter  = ", uniswapRouter, hasRole(DEFAULT_ADMIN_ROLE,uniswapRouter), hasRole(OWNER_ROLE,uniswapRouter));

        if (
            // if minted
            (from == address(0)) ||
            // or burnt itself
            (from == address(this) && to == address(0))// ||
        ) {
            //skip validation
        } else {

            uint256 balance = balanceOf(from);
            uint256 locked = tokensLocked[from]._getMinimum();
            // console.log("balance = ",balance);
            // console.log("locked  = ",locked);
            // console.log("amount  = ",amount);
            require(balance - locked >= amount, "insufficient amount");
        }

    }    

}