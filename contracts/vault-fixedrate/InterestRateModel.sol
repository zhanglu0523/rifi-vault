// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;


import "../libraries/math/SafeMath.sol";


interface IInterestRateModel {
    /// @notice calculation precision and scale of return value
    function PRECISION() external pure returns (uint256);

    /// @notice calculate interest rate after $timeInSeconds seconds
    function calculateRate(uint256 timeInSeconds) external pure returns (uint256);
}

contract InterestRateModelC1 is IInterestRateModel {
    using SafeMath for uint256;

    uint256 public constant override PRECISION = 10 ** 8;

    function calculateRate(uint256 timeInSeconds) external pure override returns (uint256) {
        uint256 x = timeInSeconds.mul(PRECISION).div(720 hours);
        uint256 xm = x.mul(10).div(9);
        return xm.mul(xm).mul(xm).div(PRECISION).div(PRECISION).div(100);
    }
}

contract InterestRateModelC2 is IInterestRateModel {
    using SafeMath for uint256;

    uint256 public constant override PRECISION = 10 ** 8;

    function calculateRate(uint256 timeInSeconds) external pure override returns (uint256) {
        uint256 x = timeInSeconds.mul(PRECISION).div(720 hours);
        uint256 x3 = x.mul(x).mul(x).div(PRECISION).div(PRECISION);
        uint256 y = (x3.mul(11).div(9)).add(x);
        return y.div(100);
    }
}

contract InterestRateModelC3 is IInterestRateModel {
    using SafeMath for uint256;

    uint256 public constant override PRECISION = 10 ** 8;

    function calculateRate(uint256 timeInSeconds) external pure override returns (uint256) {
        uint256 x = timeInSeconds.mul(PRECISION).div(720 hours);
        uint256 x2 = x.mul(x).div(PRECISION);
        uint256 x3 = x2.mul(x).div(PRECISION);
        uint256 y = (x3.mul(5).div(9)).add(x2.mul(5)).add(x.mul(10));
        return y.mul(10).div(900);
    }
}

