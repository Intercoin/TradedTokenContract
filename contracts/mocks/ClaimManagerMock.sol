// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../ClaimManagerUpgradeable.sol";

contract ClaimManagerMock is ClaimManagerUpgradeable {

    function getLastActionTime(address sender) public view returns(uint256) {
        return lastActionTime(sender);
    }
}