// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IClaimManager.sol";

interface IClaimManagerUpgradeable is IClaimManager {

    function initialize(
        address tradedToken_,
        ClaimSettings memory claimSettings,
        address costManager,
        address producedBy
    ) external;

}

