// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../interfaces/ITransferRules.sol";
import "./MockRuleSettings.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MockSRC20 is MockRuleSettings {
    
    using SafeMath for uint256;
    
    ITransferRules public _rules;
    mapping(address => uint256) public _balances;
    
    event RestrictionsAndRulesUpdated(address restrictions, address rules);
    event Transfer(address from, address to, uint256 value);
   
    // imitation SRC20 contract below
    function _updateRestrictionsAndRules(address restrictions, address rules) internal returns (bool) {

        //_restrictions = ITransferRestrictions(restrictions);
        _rules = ITransferRules(rules);

        if (rules != address(0)) {
            require(_rules.setSRC(address(this)), "SRC20 contract already set in transfer rules");
        }

        emit RestrictionsAndRulesUpdated(restrictions, rules);
        return true;
    }
    
    function executeTransfer(address from, address to, uint256 value) external/* onlyAuthority*/ returns (bool) {
        
        emit executeTransferHappens(from, to, value);
        _transfer(from, to, value);
        return true;
    }
    function updateRestrictionsAndRules(address restrictions, address rules) external /* onlyDelegate*/ returns (bool) {
        return _updateRestrictionsAndRules(restrictions, rules);
    }
    
    function transfer(address to, uint256 value) public returns (bool) {
        //require(_features.checkTransfer(msg.sender, to), "Feature transfer check");

        if (_rules != ITransferRules(address(0))) {
            require(_rules.doTransfer(msg.sender, to, value), "Transfer failed");
        } else {
            _transfer(msg.sender, to, value);
        }

        return true;
    }
    function _transfer(address from, address to, uint256 value) internal {
        require(to != address(0), "Recipient is zero address");

        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);

        //_nonce[from]++;

        emit Transfer(from, to, value);
    }
    function mint(address to, uint256 value) public {
        _balances[to] = _balances[to].add(value);
    
    }
    function balanceOf(address to) public view returns(uint256) {
        return _balances[to];
    }
}