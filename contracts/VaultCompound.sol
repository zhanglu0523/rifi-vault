// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./compound/CompoundInterface.sol";
import "./VaultInvest.sol";
import "./RewardSteward.sol";


contract VaultCompoundStorage {

    /***   State variables   ***/

    /// @notice Earned token state of an account
    struct AccountProfit {
        uint256 lastCompIndex;
        uint256 unclaimedComp;
    }
    /// @notice User earned token records
    mapping(address => AccountProfit) public userProfit;

    /// @dev Accumulated COMP per share
    uint256 public vaultCompIndex;

    /// @dev reserved for future use
    uint[20] private __gap;
}


contract VaultCompound is VaultInvest, VaultCompoundStorage {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using RewardSteward for uint256;

    /***   Constants   ***/

    CErc20Interface public immutable cToken;
    ComptrollerInterface public immutable comptroller;
    IERC20 public immutable COMP;


    /***   Constructor   ***/

    constructor(address _cTokenAddr) VaultBase() {
        // sanity check
        require(CErc20Interface(_cTokenAddr).isCToken(), "not cToken");
        ComptrollerInterface _comptroller = CErc20Interface(_cTokenAddr).comptroller();
        require(_comptroller.isComptroller(), "not Comptroller");

        cToken = CErc20Interface(_cTokenAddr);
        comptroller = _comptroller;
        COMP = IERC20(_comptroller.getCompAddress());
    }


    /***   Public functions   ***/

    /**
     * @notice Calculate account's balances of earn tokens
     * @param account The user to see earning
     * @return earning : Current account earning balance
     */
    function getEarning(address account) public virtual override returns (EarningData[] memory earning) {
        distributeDividend(account);
        earning = new EarningData[](1);
        earning[0] = EarningData({
            token: address(COMP),
            amount: userProfit[account].unclaimedComp
        });
    }


    /***   Internal machinery   ***/

    /**
     * @notice Update vault balance from Compound
     */
    function updateVaultBalance() internal virtual override {
        uint newBalance = cToken.balanceOfUnderlying(address(this));
        emit BalanceReport(totalDeposit, newBalance);
        totalDeposit = newBalance;
    }

    /**
     * @notice Update and distribute any non-interest earning / reward from Compound
     */
    function distributeDividend(address account) internal virtual override {
        uint256 earned = accrueComp();
        if (earned > 0 && totalShare > 0) {
            vaultCompIndex = vaultCompIndex.updateIndex(earned, totalShare);
            emit DistributeEarning(address(COMP), earned, totalDeposit);
        }
        AccountProfit storage user = userProfit[account];
        uint256 payout = vaultCompIndex.payoutReward(user.lastCompIndex, userDeposit[account].share);
        user.unclaimedComp = user.unclaimedComp.add(payout);
        user.lastCompIndex = vaultCompIndex;
    }

    /**
     * @dev Determine earned COMP
     * @return Amount of newly earned COMP
     */
    function accrueComp() internal virtual returns (uint256) {
        uint256 oldBalance = COMP.balanceOf(address(this));
        uint256 oldAccrued = comptroller.compAccrued(address(this));
        comptroller.claimComp(address(this));
        uint256 newBalance = COMP.balanceOf(address(this));
        uint256 newAccrued = comptroller.compAccrued(address(this));
        return newBalance.add(newAccrued).sub(oldBalance).add(oldAccrued);
    }

    /**
     * @notice Supply available cash to Compound
     * @dev Should revert on supplying failure
     * @param amount Amount to supply
     */
    function supplyDeposit(uint256 amount) internal virtual override {
        uint error = cToken.mint(amount);
        // `mint` doesn't revert but returns error code on failure
        require(error == 0, "supplying failed");
        emit Supply(amount);
    }

    /**
     * @notice Redeem requested amount from Compound
     * @dev Should revert on redeeming failure
     * @param amount Amount to redeem
     */
    function redeemDeposit(uint256 amount) internal virtual override {
        uint error = cToken.redeemUnderlying(amount);
        // `redeemUnderlying` doesn't but revert returns error code on failure
        require(error == 0, "supplying failed");
        emit Redeem(amount);
    }

    /**
     * @notice Send out earned tokens to depositor
     * @param account Account to harvest
     */
    function harvestEarnedTokens(address account) internal virtual override {
        // Payout to calculate due profit
        distributeDividend(account);

        AccountProfit storage user = userProfit[account];
        uint256 amount = user.unclaimedComp;
        if (amount > 0) {
            if (amount <= COMP.balanceOf(address(this))) {
                user.unclaimedComp = 0;
                COMP.safeTransfer(account, amount);
                emit Earn(address(COMP), account, amount);
            }
        }
    }


    /***   Admin functions   ***/

    /**
     * @notice Approve Compound to enable supplying
     */
    function approveTransfer() public virtual onlyAdmin {
        depositToken.safeApprove(address(cToken), type(uint256).max);
    }

    /**
     * @dev Initialize vault parameters
     * @param _depositToken token that user would deposit into vault
     * @param _rewardToken token that user would receive as reward for deposit
     * @param _rewardLocker assistant contract to dispense reward
     * @param _blockReward reward per block
     */
    function initializeVault(
        address _depositToken,
        address _rewardToken,
        address _rewardLocker,
        uint256 _blockReward
    ) public override initializer onlyAdmin {
        // sanity check
        require(cToken.underlying() == _depositToken, "mismatch deposit token");
        super.initializeVault(_depositToken, _rewardToken, _rewardLocker, _blockReward);
        approveTransfer();
    }

    /**
     * @dev Become the new brain of proxy
     */
    function _become(VaultProxy proxy) public override {
        super._become(proxy);
        // sanity check
        address _depositToken = address(VaultBase(address(proxy)).depositToken());
        require(_depositToken == address(0) || _depositToken == cToken.underlying(), "mismatch cToken");
    }
}

