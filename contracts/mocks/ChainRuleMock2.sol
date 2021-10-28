// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../restrictions/ChainRuleBase.sol";
import "./src20/MockRuleSettings.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract ChainRuleMock2 is ChainRuleBase, MockRuleSettings {
    using Strings for uint256;
    
    uint256 constant ind = 2;
    
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
        
        if (shouldRevert) {
            return (from, to, value, false, string(abi.encodePacked("ShouldRevert#", ind.toString())));
        } else {
            emit DoValidateHappens(ind, from, to, value);
            return (from, to, value, true, "");
        }
        
        
    }
    
}