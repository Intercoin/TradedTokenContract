// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../StakeManagerUpgradeable.sol";

contract StakeManagerMock is StakeManagerUpgradeable {

    function setBonusSharesRate(uint16 bonusSharesRate_) public {
        bonusSharesRate = bonusSharesRate_;
    }

    // it's short version of calculateRewards method
    function calculateRewardsMock(
        address sender,
        uint256 availableToClaim
    ) 
        public
        view 
        returns(uint256 rewardsToTransfer)
    {
        uint256 lastAccumulatedPerShareInternal = lastAccumulatedPerShare + MULTIPLIER * availableToClaim / sharesTotal;
        for (uint256 i = 0; i < stakes[sender].length; ++i) {
            Stake storage st = stakes[sender][i];
            if (
                // stake already ended
                st.endTime > 0 || 
                // not yet for this one
                st.startTime + st.durationMin > block.timestamp
            ) {
                continue; // stake already ended
            }
            
            uint64 lastClaimTime = st.startTime + st.lastClaimOffset;
            uint256 rewardsPerShare = lastAccumulatedPerShareInternal - accumulatedPerShare[lastClaimTime];
            rewardsToTransfer += rewardsPerShare * st.shares / MULTIPLIER;
            
        }
    }

}