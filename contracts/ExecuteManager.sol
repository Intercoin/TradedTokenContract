// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./libs/FixedPoint.sol";
import "hardhat/console.sol";
abstract contract ExecuteManager {

    uint8 private runOnlyOnceFlag;

    modifier runOnlyOnce() {
        require(runOnlyOnceFlag < 1, "already called");
        runOnlyOnceFlag = 1;
        _;
    }
}
    