// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IUniswapCustomMock {
    function sync() external;
    function price1CumulativeLast() external view returns (uint);
}