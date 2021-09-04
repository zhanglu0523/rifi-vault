// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./venus/VenusInterface.sol";
import "./VaultInvest.sol";
import "./RewardSteward.sol";


contract VaultVenusStorage {

    /***   State variables   ***/

    /// @notice Earned token state of an account
    struct AccountProfit {
        uint256 lastXvsIndex;
        uint256 unclaimedXvs;
    }
    /// @notice User earned token records
    mapping(address => AccountProfit) public userProfit;

    /// @dev Accumulated XVS per share
    uint256 public vaultXvsIndex;

    /// @dev reserved for future use
    uint[20] private __gap;
}

contract VaultVenus is VaultInvest, VaultVenusStorage {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using RewardSteward for uint256;

    /***   Constants   ***/

    VBep20Interface public immutable vToken;
    ComptrollerInterface public immutable comptroller;
    IERC20 public immutable XVS;


    /***   Constructor   ***/

    constructor(address _vTokenAddr) VaultBase() {
        // sanity check
        require(VBep20Interface(_vTokenAddr).isVToken(), "not vToken");
        ComptrollerInterface _comptroller = VBep20Interface(_vTokenAddr).comptroller();
        require(_comptroller.isComptroller(), "not Comptroller");

        vToken = VBep20Interface(_vTokenAddr);
        comptroller = _comptroller;
        XVS = IERC20(_comptroller.getXVSAddress());
    }


    /***   Public functions   ***/

    /**
     * @notice Calculate account's balances of earn tokens
     * @param account The user to see earning
     * @return earning : Current account earning balance
     */
    function getEarning(address account) public override returns (EarningData[] memory earning) {
        distributeDividend(account);
        earning = new EarningData[](1);
        earning[0] = EarningData({
            token: address(XVS),
            amount: userProfit[account].unclaimedXvs
        });
    }


    /***   Internal machinery   ***/

    /**
     * @notice Update vault balance from Venus
     */
    function updateVaultBalance() internal virtual override {
        uint newBalance = vToken.balanceOfUnderlying(address(this));
        emit BalanceReport(totalDeposit, newBalance);
        totalDeposit = newBalance;
    }

    /**
     * @notice Update and distribute any non-interest earning / reward from Venus
     */
    function distributeDividend(address account) internal virtual override {
        uint256 earned = accrueVenus();
        if (earned > 0 && totalShare > 0) {
            vaultXvsIndex = vaultXvsIndex.updateIndex(earned, totalShare);
            emit DistributeEarning(address(XVS), earned, totalDeposit);
        }
        AccountProfit storage user = userProfit[account];
        uint256 payout = vaultXvsIndex.payoutReward(user.lastXvsIndex, userDeposit[account].share);
        user.unclaimedXvs = user.unclaimedXvs.add(payout);
        user.lastXvsIndex = vaultXvsIndex;
    }

    /**
     * @dev Determine earned XVS
     * @return Amount of newly earned XVS
     */
    function accrueVenus() internal virtual returns (uint256) {
        uint256 oldBalance = XVS.balanceOf(address(this));
        uint256 oldAccrued = comptroller.venusAccrued(address(this));
        comptroller.claimVenus(address(this));
        uint256 newBalance = XVS.balanceOf(address(this));
        uint256 newAccrued = comptroller.venusAccrued(address(this));
        return newBalance.add(newAccrued).sub(oldBalance).add(oldAccrued);
    }

    /**
     * @notice Supply available cash to Venus
     * @param amount Amount to supply
     */
    function supplyDeposit(uint256 amount) internal virtual override {
        uint error = vToken.mint(amount);
        require(error == 0, "supplying failed");
        emit Supply(amount);
    }

    /**
     * @notice Redeem requested amount from Venus
     * @param amount Amount to redeem
     */
    function redeemDeposit(uint256 amount) internal virtual override {
        uint error = vToken.redeemUnderlying(amount);
        require(error == 0, "supplying failed");
        emit Redeem(amount);
    }

    /**
     * @notice Collect and send out earned tokens to depositor if possible
     * @param account Account to harvest
     */
    function harvestEarnedTokens(address account) internal virtual override {
        // Payout to calculate due profit
        distributeDividend(account);

        AccountProfit storage user = userProfit[account];
        uint256 amount = user.unclaimedXvs;
        if (amount > 0) {
            if (amount <= XVS.balanceOf(address(this))) {
                user.unclaimedXvs = 0;
                XVS.safeTransfer(account, amount);
                emit Earn(address(XVS), account, amount);
            }
        }
    }


    /***   Admin functions   ***/

    /**
     * @notice Approve Venus to enable supplying
     */
    function approveTransfer() public virtual onlyAdmin {
        depositToken.safeApprove(address(vToken), type(uint256).max);
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
        require(vToken.underlying() == _depositToken, "mismatch deposit token");
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
        require(_depositToken == address(0) || _depositToken == vToken.underlying(), "mismatch vToken");
    }
}

