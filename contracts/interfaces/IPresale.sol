// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ISale.sol";

interface IPresale is ISale {
    function endTime() external view returns (uint64);
}

