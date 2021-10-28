// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IChain.sol";

abstract contract ChainRuleBase is Ownable {
    address public _chainRuleAddr;
    
    function clearChain() public onlyOwner() {
        _setChain(address(0));
    }
    
    function setChain(address chainAddr) public onlyOwner() {
        _setChain(chainAddr);
    }
    
    //---------------------------------------------------------------------------------
    // internal  section
    //---------------------------------------------------------------------------------

    function _doValidate(
        address from, 
        address to, 
        uint256 value
    ) 
        internal
        returns (
            address _from, 
            address _to, 
            uint256 _value,
            bool _success,
            string memory _msg
        ) 
    {
        (_from, _to, _value, _success, _msg) = _validate(from, to, value);
        if (isChainExists() && _success) {
            (_from, _to, _value, _success, _msg) = IChain(_chainRuleAddr).doValidate(msg.sender, to, value);
        }
        
    }
    
    function isChainExists() internal view returns(bool) {
        return (_chainRuleAddr != address(0) ? true : false);
    }
    
    function _setChain(address chainAddr) internal {
        _chainRuleAddr = chainAddr;
    }
    
    function _validate(address from, address to, uint256 value) internal virtual returns (address, address, uint256, bool, string memory);

}
    