// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IPresale.sol";

contract PresaleMock is IPresale {
    uint64 endTimeTs;
    function setEndTime(uint64 i) public {
        endTimeTs = i;
    }
    function endTime() external view returns (uint64) {
        return endTimeTs;
    }
}