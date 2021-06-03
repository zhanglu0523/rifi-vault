pragma solidity ^0.5.16;
import "./SafeMath.sol";
import "./IBEP20.sol";

contract VaultAdminStorage {
    /**
    * @notice Administrator for this contract
    */
    address public admin;

    /**
    * @notice Pending administrator for this contract
    */
    address public pendingAdmin;

    /**
    * @notice Active brains of Rifi Vault
    */
    address public vaultImplementation;

    /**
    * @notice Pending brains of Rifi Vault
    */
    address public pendingVaultImplementation;
}

contract VaultStorage is VaultAdminStorage {
    /// @notice Main Vault Token
    IBEP20 public depositToken;

    /// @notice Reward Token
    IBEP20 public rewardToken;

    /// @notice Guard variable for re-entrancy checks
    bool internal _notEntered;

    /// @notice Total amount deposited
    uint256 public totalDeposit;

    /// @notice Accumulated reward per share
    uint256 public rewardIndex;

    /// @notice Last block at which reward was accumulated
    uint256 public lastRewardBlock;

    /// @notice Reward rate by block
    uint256 public rewardPerBlock;

    /// @notice Minimum time a deposit must be locked in the vault
    uint64 public withdrawalLockTime;

    /// @notice Info of each user.
    struct UserInfo {
        uint256 amount;
        uint256 unclaimedReward;
        uint256 rewardIndex;
        uint256 depositTime;
    }

    // Info of each user that stakes tokens.
    mapping(address => UserInfo) public userInfo;
}
