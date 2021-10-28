// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IChain {
    function doValidate(address from, address to, uint256 value) external returns (address, address, uint256, bool, string memory);
}
