// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IClaim.sol";

interface IClaimUpgradeable is IClaim {

    function initialize(
        address tradedToken_,
        ClaimSettings memory claimSettings,
        address costManager,
        address producedBy
    ) external;

}

