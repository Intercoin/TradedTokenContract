// SPDX-License-Identifier: AGPL
pragma solidity ^0.8.15;

import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";
import "@openzeppelin/contracts/token/ERC777/ERC777.sol";

//import "hardhat/console.sol";

import "./libs/SwapSettingsLib.sol";

import "./minimums/libs/MinimumsLib.sol";

import "./ExecuteManager.sol";

contract TradedToken is ERC777, IERC777Recipient, ExecuteManager {
    using MinimumsLib for MinimumsLib.UserStruct;

    uint64 internal constant LOCKUP_INTERVAL = 24*60*60; // day in seconds

    uint64 internal lockupIntervalAmount;
	uint256 internal constant FRACTION = 100000;
    uint256 public totalCumulativeClaimed;

    mapping(address => MinimumsLib.UserStruct) internal tokensLocked;

    address immutable uniswapRouter;

    address mainContract;
    uint256 buyTax;
    uint256 sellTax;

    constructor(
        string memory name,
        string memory symbol,
        uint64 lockupDuration
    ) 
        ERC777(name, symbol, new address[](0)) 
    {

        lockupIntervalAmount = lockupDuration;
        (uniswapRouter, /*uniswapRouterFactory*/) = SwapSettingsLib.netWorkSettings();
    //    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        mainContract = msg.sender;

      //  _setRoleAdmin(CLAIM_ROLE, CLAIM_ROLE);
    }

    modifier onlyMain() {
        require (msg.sender == mainContract, '');
        _;
    }
    
    
    function setBuyTax(
        uint256 fraction
    )
        onlyMain
        external
    {
        buyTax = fraction;
    }

    function setSellTax(
        uint256 fraction
    )
        onlyMain
        external
    {
        sellTax = fraction;
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
        uint256 tradedTokenAmount,
        bool lockup
    ) 
        public 
        onlyMain 

    {
        totalCumulativeClaimed += tradedTokenAmount;

        _mint(account, tradedTokenAmount, "", "");
        if (
            lockup
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
    //     onlyMain
    //     runOnlyOnce
    // {
        
    // }

    // ////////////onlyMain////////////////////////////////////////////////////////////
    // // internal section ////////////////////////////////////////////////////
    // ////////////////////////////////////////////////////////////////////////

    function _beforeTokenTransfer(
        address /*operator*/,
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
        // console.log("operator       = ", operator, hasRole(DEFAULT_ADMIN_ROLE,operator), hasRole(CLAIM_ROLE,operator));
        // console.log("from           = ", from, hasRole(DEFAULT_ADMIN_ROLE,from), hasRole(CLAIM_ROLE,from));
        // console.log("to             = ", to, hasRole(DEFAULT_ADMIN_ROLE,to), hasRole(CLAIM_ROLE,to));
        // console.log("----------------------");
        // console.log("address(this)  = ", address(this), hasRole(DEFAULT_ADMIN_ROLE,address(this)), hasRole(CLAIM_ROLE,address(this)));
        // console.log("owner()        = ", owner(), hasRole(DEFAULT_ADMIN_ROLE,owner()), hasRole(CLAIM_ROLE,owner()));
        // console.log("uniswapRouter  = ", uniswapRouter, hasRole(DEFAULT_ADMIN_ROLE,uniswapRouter), hasRole(CLAIM_ROLE,uniswapRouter));

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

    function _send(
        address from,
        address to,
        uint256 amount,
        bytes memory userData,
        bytes memory operatorData,
        bool requireReceptionAck
    ) internal virtual {

        
        if (uniswapV2Pair == from) {
            amount -= amount*buyTax/FRACTION;
            _burn(from, amount*buyTax/FRACTION);
        }
        if (uniswapV2Pair == to) {
            amount -= amount*sellTax/FRACTION;
            _burn(to, amount*sellTax/FRACTION);
        }
        
        super._send(from, to, amount, userData, operatorData, requireReceptionAck);

        // require(from != address(0), "ERC777: transfer from the zero address");
        // require(to != address(0), "ERC777: transfer to the zero address");

        // address operator = _msgSender();

        // _callTokensToSend(operator, from, to, amount, userData, operatorData);

        // _move(operator, from, to, amount, userData, operatorData);

        // _callTokensReceived(operator, from, to, amount, userData, operatorData, requireReceptionAck);
    }

}