// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

interface IUniswapCustom {
    //IUniswapV2Pair
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function token0() external view returns (address);

    //IUniswapV2Factory
    function createPair(address tokenA, address tokenB) external returns (address pair);

    //IUniswapV2Router02
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
}