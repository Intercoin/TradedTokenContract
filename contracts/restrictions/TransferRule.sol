// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


// Make new TransferRules contract, with constructor parameter (tradedToken, lockupDuration=WEEK, lockupFraction = 90000). 
// It will allow owner to setChain(contract). During transfer it will definitely do its own checks first, and revert if necessary. 
// Otherwise, it will call a method “check()” of next contract in the chain. If it reverts or throws exception then just dont catch it. 

// The checks include: if _until[from] > now then do two checks:
// 1) if to = TradedTokenContract, revert with message “you recently claimed new tokens, please wait until duration has elapsed to claim again”

// 2) after transfer, address would have less balance than _minimums[from] then revert with message: “you recently claimed new tokens, please wait until duration has elapsed to transfer this many tokens” 

// Later we will renounceOwnership on the ITR contract, so we will not be able to mint, forceTransfer or change rules. 
// We will still be owner of the RulesContract, but unable to remove the restrictions in it, only add additional restrictions.

// Anyway, this TransferRules will have constructor parameter to set the 0x11111 TradedTokenContract address. 
// Anytime tokens are sent to this address it will doTransfer, and AFTER this will call tradedToken.claim(from)

// And after successful claim, it will add a minimum = (current claimToken balance * afterClaimLockup / 100000) required to be held in balance until now + duration.

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ChainRuleBase.sol";

import "../interfaces/ITransferRules.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/IITR.sol";

contract TransferRule is Ownable, ITransferRules, ChainRuleBase {
    using SafeMath for uint256;
    
    address public _src20;
    address public doTransferCaller;

    uint256 internal constant MULTIPLIER = 100000;
    
    address public _tradedToken;
    uint256 public _lockupDuration;
    uint256 public _lockupFraction;
    
    struct Item {
        uint256 untilTime;
        uint256 lockedAmount;
        
    }
    mapping(address => Item) restrictions;
    
    modifier onlyDoTransferCaller {
        require(msg.sender == address(doTransferCaller));
        _;
    }
    
    //---------------------------------------------------------------------------------
    // public  section
    //---------------------------------------------------------------------------------
    /**
     * @param tradedToken tradedToken
     * @param lockupDuration duration in sec 
     * @param lockupFraction fraction in percent to lock. multiplied by MULTIPLIER
     */
    constructor(
        address tradedToken,
        uint256 lockupDuration,
        uint256 lockupFraction
    ) 
    {
        _tradedToken = tradedToken;
        _lockupDuration = lockupDuration;
        _lockupFraction = lockupFraction;
    }
    
    function cleanSRC() public onlyOwner() {
        _src20 = address(0);
        doTransferCaller = address(0);
        //_setChain(address(0));
    }
    
    //---------------------------------------------------------------------------------
    // external  section
    //---------------------------------------------------------------------------------
    /**
    * @dev Set for what contract this rules are.
    *
    * @param src20 - Address of src20 contract.
    */
    function setSRC(address src20) override external returns (bool) {
        require(doTransferCaller == address(0), "external contract already set");
        require(address(_src20) == address(0), "external contract already set");
        require(src20 != address(0), "src20 can not be zero");
        doTransferCaller = _msgSender();
        _src20 = src20;
        return true;
    }
     /**
    * @dev Do transfer and checks where funds should go.
    * before executeTransfer contract will call chainValidate on chain if exists
    *
    * @param from The address to transfer from.
    * @param to The address to send tokens to.
    * @param value The amount of tokens to send.
    */
    function doTransfer(address from, address to, uint256 value) override external onlyDoTransferCaller returns (bool) {
        bool success;
        string memory errmsg;
        
        (from, to, value, success, errmsg) = _doValidate(from, to, value);
        
        
        require(success, (bytes(errmsg).length == 0) ? "chain validation failed" : errmsg);
        
        // todo: need to check params after chains validation??
        
        require(ISRC20(_src20).executeTransfer(from, to, value), "SRC20 transfer failed");
        
        
        if (
            success && (to == _tradedToken)
        ) {
            
            IITR(_tradedToken).claim(from);
            
        }
        
        
        return true;
    }
    //---------------------------------------------------------------------------------
    // internal  section
    //---------------------------------------------------------------------------------
    function _validate(address from, address to, uint256 value) internal virtual override returns (address _from, address _to, uint256 _value, bool _success, string memory _errmsg) {
        
        (_from, _to, _value, _success, _errmsg) = (from, to, value, true, "");
// The checks include: if _until[from] > now then do two checks:        
// 1) if to = TradedTokenContract, revert with message “you recently claimed new tokens, please wait until duration has elapsed to claim again”
// 2) after transfer, address would have less balance than _minimums[from] then revert with message: “you recently claimed new tokens, please wait until duration has elapsed to transfer this many tokens” 

        uint256 balanceFrom = ISRC20(_src20).balanceOf(from);
        
        if (restrictions[from].untilTime > block.timestamp) {
            if (to == _tradedToken) {
                _success = false;
                _errmsg = "you recently claimed new tokens, please wait until duration has elapsed to claim again";
            } else if ((restrictions[from].lockedAmount).add(value) > balanceFrom) {
                _success = false;
                _errmsg = "you recently claimed new tokens, please wait until duration has elapsed to transfer this many tokens";
            }
        }
        
        
        if (
            _success && 
            (to == _tradedToken) &&
            (restrictions[from].untilTime > block.timestamp)
        ) {
            
            restrictions[from].untilTime = (block.timestamp).add(_lockupDuration);
            restrictions[from].lockedAmount = (balanceFrom.sub(value)).mul(_lockupFraction).div(MULTIPLIER);
        
        }
        
        
        
    }
    
    //---------------------------------------------------------------------------------
    // private  section
    //---------------------------------------------------------------------------------

}
    