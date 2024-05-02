// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IStake.sol";

interface IStakeUpgradeable is IStake {

    function initialize(
        address tradedToken,
        address stakingToken,
        uint16 bonusSharesRate, // = 100,
        uint64 defaultStakeDuration, // = WEEK,
        address costManager,
        address producedBy
    ) external;

}

