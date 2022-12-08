// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../old/ITR.sol";

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
        
        _claimToken = addr;
        _claimDuration = duration;
        _claimFraction = fraction;
        _claimExcepted = excepted;
        _claimGrowth = growth;
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
        addr = _claimToken;
        duration = _claimDuration;
        fraction = _claimFraction;
        excepted = _claimExcepted;
        growth = _claimGrowth;
    }
    
    function getCurrentClaimedAmount() public view returns(uint256) {
        return _lastClaimedAmount;
    }
    function setCurrentClaimedAmount(uint256 input) public {
        _lastClaimedAmount = input;
    }
    
    // function getMaxTotalSupply() public view returns(uint256) {
    //     return _maxTotalSupply;
    // }
    
    function setMaxTotalSupply(uint256 input) public {
        _maxTotalSupply = input;
    }
    
}