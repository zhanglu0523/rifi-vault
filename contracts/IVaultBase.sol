// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;


interface IVaultBase {

    /***   Events   ***/

    /// @notice Emitted on deposit
    event Deposit(address indexed user, uint256 amount, uint256 share);

    /// @notice Emitted on withrawal
    event Withdraw(address indexed user, uint256 amount, uint256 share);

    /// @notice Emitted on harvest
    event Harvest(address indexed user, uint256 amount);

    /// @notice Emitted on reward distribution
    event DistributeReward(uint256 amount, uint256 deposit);

    /// @notice Emitted when block reward changed
    event NewRewardRate(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when Reward locker changed
    event NewRewardLocker(address oldRewardLocker, address newRewardLocker);

    /// @notice Emitted when reward release block changed
    event NewReleaseBlock(uint256 oldReleaseBlock, uint256 newReleaseBlock);

    /***   Public functions   ***/

    /**
     * @notice Deposit token to vault
     * @param amount The amount to deposit to vault
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Deposit token to vault
     * @param amount The amount to deposit to vault
     */
    function depositFor(address account, uint256 amount) external;

    /**
     * @notice Withdraw token from vault
     * @param amount The amount to withdraw from vault
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Withdraw everything and harvest remaining reward
     */
    function withdrawAll() external;

    /**
     * @notice Harvest pending reward and start vesting
     */
    function harvest() external;


    /**
     * @notice View function to see balance of an account
     * @param account The user to see balance
     */
    function getBalance(address account) external view returns (uint256);

    /**
     * @notice View function to see total unclaimed reward on frontend
     * @param account The user to see unclaimed reward
     */
    function getUnclaimedReward(address account) external view returns (uint256);
}

interface IVaultInvest is IVaultBase {

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
    event Earn(address indexed token, address indexed user, uint256 amount);


    /***   Public functions   ***/

    /**
     * @notice Calculate account's current balance, with interests
     * @param account The user to see balance
     * @return Current account balance
     */
    function getCurrentBalance(address account) external returns (uint256);

    struct EarningData {
        address token;
        uint amount;
    }

    /**
     * @notice Calculate account's balances of earn tokens
     * @param account The user to see earning
     * @return earning : Current account earning balance for each earned token
     */
    function getEarning(address account) external returns (EarningData[] memory earning);
}
