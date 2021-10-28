// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ChainRuleBase.sol";

contract ChainRule is ChainRuleBase {

    function doValidate(
        address from, 
        address to, 
        uint256 value
    ) 
        external 
        returns (address, address, uint256, bool, string memory) 
    {
        //(_from, _to, _value, _success) = _doValidate(from, to, value);
        return _doValidate(from, to, value);
    }
    
    function _validate(address from, address to, uint256 value) internal virtual override returns (address, address, uint256, bool, string memory) {
        // valdiate rules must be here
        
        
        // for example: return bypass(data as is and successfull true) 
        return (from, to, value, true, "");
    }
  
}
    