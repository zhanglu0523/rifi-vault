// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./aave/AaveInterface.sol";
import "./VaultInvest.sol";
import "./RewardSteward.sol";


contract VaultAaveStorage {

    /***   State variables   ***/

    /// @notice Earned token state of an account
    struct AccountProfit {
        uint256 lastAaveIndex;
        uint256 unclaimedAave;
    }
    /// @notice User earned token records
    mapping(address => AccountProfit) public userProfit;

    /// @dev Accumulated AAVE per share
    uint256 public vaultAaveIndex;

    /// @dev reserved for future use
    uint[20] private __gap;

}

contract VaultAave is VaultInvest, VaultAaveStorage {
    using SafeMath for uint256;
    using RewardSteward for uint256;
    using SafeERC20 for IERC20;

    /***   Constants   ***/

    ILendingPool public immutable lendingPool;
    IAToken public immutable aToken;
    IERC20 public immutable AAVE;
    IAaveIncentivesController public immutable incentiveController;
    bool public immutable giveAave;


    /***   Constructor   ***/

    constructor(address _aTokenAddr, address _aaveAddr) VaultBase() {
        aToken = IAToken(_aTokenAddr);
        lendingPool = ILendingPool(IAToken(_aTokenAddr).POOL());
        AAVE = IERC20(_aaveAddr);
        // sometimes, the aToken just doesn't have it
        IAaveIncentivesController _icAddr;
        bool _giveAave;
        try IAToken(_aTokenAddr).getIncentivesController()
        returns (IAaveIncentivesController addr) {
            _icAddr = addr;
            _giveAave = true;
        } catch {
            _icAddr = IAaveIncentivesController(0);
            _giveAave = false;
        }
        incentiveController = _icAddr;
        giveAave = _giveAave;
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
            token: address(AAVE),
            amount: userProfit[account].unclaimedAave
        });
    }


    /***   Internal machinery   ***/

    /**
     * @notice Update vault balance from Aave
     */
    function updateVaultBalance() internal virtual override {
        uint newBalance = aToken.balanceOf(address(this));
        emit BalanceReport(totalDeposit, newBalance);
        totalDeposit = newBalance;
    }

    /**
     * @notice Update and distribute any non-interest earning / reward from Aave
     */
    function distributeDividend(address account) internal virtual override {
        uint256 earned = accrueAave();
        if (earned > 0 && totalShare > 0) {
            vaultAaveIndex = vaultAaveIndex.updateIndex(earned, totalShare);
            emit DistributeEarning(address(AAVE), earned, totalDeposit);
        }
        AccountProfit storage user = userProfit[account];
        uint256 payout = vaultAaveIndex.payoutReward(user.lastAaveIndex, userDeposit[account].share);
        user.unclaimedAave = user.unclaimedAave.add(payout);
        user.lastAaveIndex = vaultAaveIndex;
    }

    /**
     * @dev Determine earned AAVE
     * @return Amount of newly earned AAVE
     */
    function accrueAave() internal virtual returns (uint256) {
        if (!giveAave) {
            return 0;
        }

        address[] memory assets = new address[](1);
        assets[0] = address(depositToken);
        uint256 unclaimedAmount = incentiveController.getRewardsBalance(assets, address(this));
        uint256 rewardReceived = incentiveController.claimRewards(assets, unclaimedAmount, address(this));
        return rewardReceived;
    }

    /**
     * @notice Supply available cash to Aave
     * @param amount Amount to supply
     */
    function supplyDeposit(uint256 amount) internal virtual override {
        lendingPool.deposit(address(depositToken), amount, address(this), 0);
        emit Supply(amount);
    }

    /**
     * @notice Redeem requested amount from Aave
     * @param amount Amount to redeem
     */
    function redeemDeposit(uint256 amount) internal virtual override {
        lendingPool.withdraw(address(depositToken), amount, address(this));
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
        uint256 amount = user.unclaimedAave;
        if (amount > 0) {
            if (amount <= AAVE.balanceOf(address(this))) {
                user.unclaimedAave = 0;
                AAVE.safeTransfer(account, amount);
                emit Earn(address(AAVE), account, amount);
            }
        }
    }


    /***   Admin functions   ***/

    /**
     * @notice Approve Aave to enable supplying
     */
    function approveTransfer() public virtual onlyAdmin {
        depositToken.safeApprove(address(lendingPool), type(uint256).max);
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
        require(aToken.UNDERLYING_ASSET_ADDRESS() == _depositToken, "mismatch deposit token");
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
        require(_depositToken == address(0) || _depositToken == aToken.UNDERLYING_ASSET_ADDRESS(), "mismatch aToken");
    }
}

