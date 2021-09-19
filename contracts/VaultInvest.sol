// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./VaultBase.sol";


abstract contract VaultInvest is VaultBase {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /***   Constants   ***/

    uint internal constant DUST_AMOUNT = 10;

    /***   Events   ***/

    /// @notice Emitted after updating vault balance
    event BalanceReport(uint256 oldBalance, uint256 newBalance);

    /// @notice Emitted on earned tokens distribution
    event DistributeEarning(address indexed token, uint256 amount, uint256 deposit);

    /// @notice Emitted when supplying to farm
    event Supply(uint256 amount);

    /// @notice Emitted when redeeming from farm
    event Redeem(uint256 amount);

    /// @notice Emitted when user claim earned tokens
    event Earn(address indexed token, address indexed account, uint256 amount);


    /***   Modifiers   ***/

    /**
     * @dev Update investment status before any action
     */
    modifier updateInvest(address account) {
        // Vault balance must be up-to-date for correct share value
        updateVaultBalance();
        // Payout to current shareholders before changing share total
        distributeDividend(account);

        _;
    }

    /***   Public functions   ***/

    /**
     * @notice Harvest pending reward and start vesting
     */
    function harvest() public virtual override whenNotPaused nonReentrant {
        harvestInternal(_msgSender());
        harvestEarnedTokens(_msgSender());
    }

    /**
     * @notice Calculate account's current balance, with interests
     * @param account The user to see balance
     * @return Current account balance
     */
    function getCurrentBalance(address account) public virtual returns (uint256) {
        updateVaultBalance();
        return getBalance(account);
    }

    struct EarningData {
        address token;
        uint amount;
    }

    /**
     * @notice Calculate account's balances of earn tokens
     * @param account The user to see earning
     * @return earning : Current account earning balance for each earned token
     */
    function getEarning(address account) public virtual returns (EarningData[] memory earning);


    /***   Internal machinery   ***/

    /**
     * @notice Internal function to handle deposit
     * @dev Must be protected from reentrancy by caller
     * @param account The account to deposit to vault
     * @param amount The amount to deposit to vault
     * @param spender The account to transfer token from (can be different to $account)
     */
    function depositInternal(address account, uint256 amount, address spender) internal virtual override updateInvest(account) {

        uint256 oldTotal = totalDeposit;
        super.depositInternal(account, amount, spender);

        // Avoid off-by-one "error" on new deposit due to non-integer share value
        if (getBalance(account) < amount) {
            AccountDeposit storage user = userDeposit[account];
            user.share = user.share.add(1);
            totalShare = totalShare.add(1);
        }

        // Should revert on supplying failure
        supplyDeposit(totalDeposit.sub(oldTotal));
    }

    /**
     * @notice Low level withdraw function
     * @dev Must be protected from reentrancy by caller
     * @param account The account to withdraw
     * @param amount The amount to withdraw from vault
     */
    function withdrawInternal(address account, uint256 amount) internal virtual override updateInvest(account) {
        // Should revert on redeeming failure
        redeemDeposit(amount);
        super.withdrawInternal(account, amount);
    }

    /**
     * @notice Internal function to withdraw everything
     * @param account The account to withdraw
     */
    function withdrawAllInternal(address account) internal virtual override updateInvest(account) {
        uint256 amount = getBalance(account);
        redeemDeposit(amount);
        super.withdrawInternal(account, amount);

        // Remove dust shares and rounding left-over
        if (getBalance(account) < DUST_AMOUNT) {
            AccountDeposit storage user = userDeposit[account];
            totalShare = totalShare.sub(user.share);
            user.share = 0;
        }

        harvestEarnedTokens(account);
    }

    /**
     * @notice Update vault balance with interest
     */
    function updateVaultBalance() internal virtual;

    /**
     * @notice Update and distribute any non-interest earning / reward
     */
    function distributeDividend(address account) internal virtual;

    /**
     * @notice Supply available cash
     * @param amount Amount to supply
     */
    function supplyDeposit(uint256 amount) internal virtual;

    /**
     * @notice Redeem requested amount
     * @param amount Amount to redeem
     */
    function redeemDeposit(uint256 amount) internal virtual;

    /**
     * @notice Collect and send out earned tokens to depositor if possible
     * @param account Account to harvest
     */
    function harvestEarnedTokens(address account) internal virtual;
}

