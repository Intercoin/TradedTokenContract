// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ClaimManager.sol";

contract ClaimManagerMock is ClaimManager {

    constructor (
        address tradedToken,
        ClaimSettings memory claimSettings
        
    ) 
        ClaimManager (tradedToken, claimSettings)
    {
    }

    function getLastActionTime(address sender) public view returns(uint256) {
        return lastActionTime(sender);
    }
}