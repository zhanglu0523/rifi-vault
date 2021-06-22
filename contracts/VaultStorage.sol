// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;


import "./libraries/token/IERC20.sol";
import "./IRewardLocker.sol";


contract VaultAdminStorage {
    /**
    * @dev Administrator for this contract
    */
    address internal admin;

    /**
    * @dev Pending administrator for this contract
    */
    address internal pendingAdmin;

    /**
    * @dev Active brains of Rifi Vault
    */
    address internal vaultImplementation;

    /**
    * @dev Pending brains of Rifi Vault
    */
    address internal pendingVaultImplementation;
}

contract VaultStorage is VaultAdminStorage {

    /// @notice Main Vault Token
    IERC20 public depositToken;
    /// @notice Reward Token
    IERC20 public rewardToken;

    /// @notice Reward locker
    IRewardLocker public rewardLocker;


    /***   Deposit state   ***/

    /// @notice Deposit state of an account
    struct AccountDeposit {
        uint256 share;
        uint256 lastDepositTime;
    }
    /// @notice User deposit records
    mapping(address => AccountDeposit) public userDeposit;

    /// @notice Total share issued
    uint256 public totalShare;
    /// @notice Amount of deposit the vault think it's holding
    uint256 public totalDeposit;
    /// @notice Number of current depositors
    uint256 public totalUsers;


    /***   Reward state   ***/

    /// @notice Reward rate by block
    uint256 public rewardPerBlock;
    /// @notice Accumulated reward per share
    uint256 public rewardIndex;
    /// @notice Last block at which reward was accumulated
    uint256 public lastRewardBlock;

    /// @notice Reward state of an account
    struct AccountReward {
        uint256 rewardIndex;
    }
    /// @notice User reward records
    mapping(address => AccountReward) public userReward;
}
