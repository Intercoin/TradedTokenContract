// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IStake {

    struct Stake {
        uint64 startTime; // timestamp
        uint64 endTime; // timestamp
        uint32 durationMin; // seconds since startTime
        uint32 lastClaimOffset; // seconds since startTime
        uint32 shares; // number of shares in stake
        uint32 amount; // amount of StakingToken staked
    }

    function stake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function rewards(address who) external view returns(uint256 tradedTokenAmount);
    function claim() external;
    function claimToAddress(address to) external;
}
