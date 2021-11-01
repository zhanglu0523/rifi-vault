// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;


import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';

import "../libraries/math/SafeMath.sol";


interface ILPConverter {
    function convertLPToken(uint256 amount, address from, address to) external view returns (uint256);
}

contract UniswapV2LPConverter is ILPConverter {
    using SafeMath for uint256;

    function convertLPToken(uint256 amount, address from, address to) external view override returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(from);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        uint256 lpTotal = pair.totalSupply();
        if (pair.token0() == to) {
            return amount.mul(uint256(reserve0)).div(lpTotal).mul(2);
        } else if (pair.token1() == to) {
            return amount.mul(uint256(reserve1)).div(lpTotal).mul(2);
        } else {
            revert("convertLPToken: invalid $to token");
        }
    }
}
