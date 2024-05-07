// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITradedToken {
    // TODO: implement the rest of the interface, if needed
    //function pauseBuy(bool status) external;

    function availableToClaim() external view returns(uint256);
    function claim(uint256 tradedTokenAmount, address account) external;
}

