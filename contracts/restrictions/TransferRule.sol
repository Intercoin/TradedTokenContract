// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./ChainRuleBase.sol";

import "../interfaces/ITransferRules.sol";
import "../interfaces/ISRC20.sol";
import "../interfaces/IITR.sol";

contract TransferRule is Ownable, ITransferRules, ChainRuleBase {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    
    address public _src20;
    address public _doTransferCaller;

    uint256 internal constant MULTIPLIER = 100000;
    
    address public _tradedToken;
    uint256 public _lockupDuration;
    uint256 public _lockupFraction;
    
    struct Item {
        uint256 untilTime;
        uint256 lockedAmount;
        
    }
    mapping(address => Item) restrictions;
    
    EnumerableSet.AddressSet _exchangeDepositAddresses;
    
    modifier onlyDoTransferCaller {
        require(msg.sender == address(_doTransferCaller));
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
        _doTransferCaller = address(0);
        //_setChain(address(0));
    }
    
    
    function addExchangeAddress(address addr) public onlyOwner() {
        _exchangeDepositAddresses.add(addr);
    }
    
    function removeExchangeAddress(address addr) public onlyOwner() {
        _exchangeDepositAddresses.remove(addr);
    }
    
    function viewExchangeAddresses() public view returns(address[] memory) {
        uint256 len = _exchangeDepositAddresses.length();
        
        address[] memory ret = new address[](len);
        for (uint256 i =0; i < len; i++) {
            ret[i] = _exchangeDepositAddresses.at(i);
        }
        return ret;
        
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
        require(_doTransferCaller == address(0), "external contract already set");
        require(address(_src20) == address(0), "external contract already set");
        require(src20 != address(0), "src20 can not be zero");
        _doTransferCaller = _msgSender();
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

        require(
            _exchangeDepositAddresses.contains(to) == false, 
            string(abi.encodePacked("Don't deposit directly to this exchange. Send to the address ITR.ETH first, to obtain the correct token in your wallet."))
        );
        
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
    