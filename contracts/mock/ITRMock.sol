// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ITR.sol";

contract ITRMock is ITR {
   
    
    function setClaimData(
        address addr,
        uint256 duration,
        uint256 fraction,
        uint256 excepted,
        uint256 growth
    ) 
        public 
    {
        
        claimToken = addr;
        claimDuration = duration;
        claimFraction = fraction;
        claimExcepted = excepted;
        claimGrowth = growth;
    }
    
    function getClaimData(
    ) 
        public
        view
        returns(
            address addr,
            uint256 duration,
            uint256 fraction,
            uint256 excepted,
            uint256 growth
        )
    {
        addr = claimToken;
        duration = claimDuration;
        fraction = claimFraction;
        excepted = claimExcepted;
        growth = claimGrowth;
    }
    
    function getCurrentClaimedAmount() public view returns(uint256) {
        return lastClaimedAmount;
    }
    function setCurrentClaimedAmount(uint256 input) public {
        lastClaimedAmount = input;
    }
    
    function getMaxTotalSupply() public view returns(uint256) {
        return _maxTotalSupply;
    }
    function setMaxTotalSupply(uint256 input) public {
        _maxTotalSupply = input;
    }
    
}