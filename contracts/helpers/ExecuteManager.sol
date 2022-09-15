// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract ExecuteManager {
    uint8 private runOnlyOnceFlag;

    modifier runOnlyOnce() {
        require(runOnlyOnceFlag < 1, "already called");
        runOnlyOnceFlag = 1;
        _;
    }
}
