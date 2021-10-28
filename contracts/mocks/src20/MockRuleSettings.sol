// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockRuleSettings {
    bool shouldRevert;
    event DoTransferHappens(uint256 i, address from, address to, uint256 value);
    event DoValidateHappens(uint256 i, address from, address to, uint256 value);
    event executeTransferHappens(address from, address to, uint256 value);
    
    function setRevertState(bool b) public {
        shouldRevert = b;
    }
}