// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import "./libraries/token/IERC20.sol";
import "./RewardLocker.sol";

library RewardSteward {
    using SafeMath for uint256;

    uint internal constant FRACTIONAL_SCALE = 1e18;

    function updateIndex(uint256 currentIndex, uint256 amount, uint256 totalShare) internal pure
            returns(uint256 newIndex) {
        if (amount == 0 || totalShare == 0) {
            return currentIndex;
        } else {
            return amount.mul(FRACTIONAL_SCALE).div(totalShare).add(currentIndex);
        }
    }

    function payoutReward(uint256 vaultIndex, uint256 userIndex, uint256 share) internal pure
            returns (uint256 payoutAmount) {
        payoutAmount = vaultIndex.sub(userIndex).mul(share).div(FRACTIONAL_SCALE);
    }
}
