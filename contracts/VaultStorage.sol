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

    /// @dev Amount of deposit the vault thinks it's holding
    uint256 public totalDeposit;
    /// @dev Total share issued
    uint256 public totalShare;

    /// @notice Deposit state of an account
    struct AccountDeposit {
        uint256 share;
        uint256 lastDepositTime;
    }
    /// @notice User deposit records
    mapping(address => AccountDeposit) public userDeposit;


    /***   Reward state   ***/

    /// @dev Reward rate by block
    uint256 public rewardPerBlock;
    /// @dev Accumulated reward per share
    uint256 public rewardIndex;
    /// @dev Last block at which reward was distributed
    uint256 public lastRewardBlock;

    /// @notice Reward state of an account
    struct AccountReward {
        uint256 rewardIndex;
    }
    /// @notice User reward records
    mapping(address => AccountReward) public userReward;

    /// @notice Block number at which to start releasing reward
    uint256 public lockReleaseBlock;

    /// @dev reserved for future use
    uint[19] private __gap;
}
