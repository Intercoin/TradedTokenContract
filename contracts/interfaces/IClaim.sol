// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IClaim {
    function claim(uint256 amount, address account) external;   
    function availableToClaim() external view returns(uint256 tradedTokenAmount);
    
}
