// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;


import "./libraries/math/SafeMath.sol";
import "./libraries/token/IERC20.sol";
import "./libraries/token/SafeERC20.sol";
import "./libraries/security/ReentrancyGuard.sol";
import "./libraries/security/Pausable.sol";
import "./libraries/utils/Initializable.sol";
import "./VaultProxy.sol";
import "./VaultStorage.sol";
import "./VaultErrorReporter.sol";


contract Vault is VaultStorage, VaultImplementation, Context, Pausable, Initializable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint private constant FRACTIONAL_SCALE = 1e18;

    /***   Events   ***/

    /// @notice Emitted on deposit
    event Deposit(address indexed user, uint256 amount, uint256 share);

    /// @notice Emitted on withrawal
    event Withdraw(address indexed user, uint256 amount, uint256 share);

    /// @notice Emitted on harvest
    event Harvest(address indexed user, uint256 amount);

    /// @notice Emitted on reward distribution
    event DistributeReward(uint256 amount);

    /// @notice Emitted when block reward changed
    event NewRewardRate(uint256 oldRate, uint256 newRate);

    /// @notice Emitted when Reward locker changed
    event NewRewardLocker(address oldRewardLocker, address newRewardLocker);


    /***   Modifiers   ***/

    constructor() Pausable() ReentrancyGuard() {
    // constructor() {
        // when `admin` is a regular state variable
        admin = address(0);     // disable direct "admin" interaction with logic contract
    }

    /**
     * @dev Returns the current admin.
     * Copied from VaultProxy.
     */
    function _getAdmin() internal view returns (address) {
        // when `admin` is a regular state variable
        return admin;
    }

    /**
     * @dev Modifier to limit access of administration functions
     */
    modifier onlyAdmin() {
        require(_msgSender() == _getAdmin(), "not admin");
        _;
    }


    /***   Public functions   ***/

    /**
     * @notice Deposit token to vault
     * @param amount The amount to deposit to vault
     */
    function deposit(uint256 amount) public whenNotPaused nonReentrant {
        depositInternal(_msgSender(), amount);
    }

    /**
     * @notice Withdraw token from vault
     * @param amount The amount to withdraw from vault
     */
    function withdraw(uint256 amount) public whenNotPaused nonReentrant {
        // in case rounding error cause slight difference when converting back to share
        if (getBalance(_msgSender()) == amount) {
            withdrawAllInternal(_msgSender());
        } else {
            withdrawInternal(_msgSender(), _amountToShare(amount));
        }
    }

    /**
     * @notice Withdraw everything and harvest remaining reward
     */
    function withdrawAll() public whenNotPaused nonReentrant {
        withdrawAllInternal(_msgSender());
    }

    /**
     * @notice Harvest pending reward and start vesting
     */
    function harvest() public whenNotPaused nonReentrant {
        harvestInternal(_msgSender());
    }

    /**
     * @notice Endow an amount of reward tokens to the vault, split equally among all current deposit shares
     * @param amount An optional extra amount of reward from caller account
     */
    function endowReward(uint256 amount) public nonReentrant {
        // Can not distribute reward on empty vault
        require(totalDeposit > 0, "Endow: no deposit");

        // In case amount received is less than requested
        uint256 actualEndowment = _checkedTransferFrom(rewardToken, _msgSender(), amount);
        rewardIndex = _newRewardIndex(actualEndowment);
        if (actualEndowment > 0) {
            rewardToken.safeTransfer(address(rewardLocker), actualEndowment);
            emit DistributeReward(actualEndowment);
        }
    }

    /**
     * @notice View function to see balance of an account
     * @param account The user to see unclaimed reward
     */
    function getBalance(address account) public view returns (uint256) {
        return _shareToAmount(userDeposit[account].share);
    }

    /**
     * @notice View function to see total unclaimed reward on frontend
     * @param account The user to see unclaimed reward
     */
    function getUnclaimedReward(address account) public view returns (uint256) {
        uint256 currentRewardIndex = _newRewardIndex(_pendingBlockReward());
        return currentRewardIndex.sub(userReward[account].rewardIndex).mul(userDeposit[account].share).div(FRACTIONAL_SCALE);
    }


    /***   Internal machinery   ***/

    /**
     * @notice Internal function to handle deposit
     * @dev Must be protected from reentrancy by caller
     * @param account The account to deposit to vault
     * @param amount The amount to deposit to vault
     */
    function depositInternal(address account, uint256 amount) internal {
        // Must update vault reward before total changes
        updateVaultRewardInternal();
        // Must update account reward before changing deposit
        accumulateReward(account);

        // Transfer in the amount from user
        uint256 received = _checkedTransferFrom(depositToken, account, amount);
        uint256 newShare = _amountToShare(received);

        // Update state
        AccountDeposit storage user = userDeposit[account];
        if (user.share == 0 && newShare > 0) {
            totalUsers = totalUsers.add(1);
        }
        user.lastDepositTime = block.timestamp;
        user.share = user.share.add(newShare);
        totalShare = totalShare.add(newShare);
        totalDeposit = totalDeposit.add(received);

        emit Deposit(account, received, newShare);
    }

    /**
     * @notice Low level withdraw function
     * @param account The account to withdraw from vault
     * @param share The number of share to withdraw from vault
     */
    function withdrawInternal(address account, uint256 share) internal {
        AccountDeposit storage user = userDeposit[account];
        require(user.share >= share, "Withdraw: exceed user balance");

        // Must update vault reward before total changes
        updateVaultRewardInternal();
        // Must update account reward before changing deposit
        accumulateReward(account);

        // Update state
        uint256 amount = _shareToAmount(share);
        if (share == user.share && user.share > 0) {
            totalUsers = totalUsers.sub(1);
            user.lastDepositTime = 0;
        }
        user.share = user.share.sub(share);
        totalShare = totalShare.sub(share);
        totalDeposit = totalDeposit.sub(amount);

        // Transfer tokens to user
        depositToken.safeTransfer(account, amount);

        emit Withdraw(account, amount, share);
    }

    /**
     * @notice Internal function to withdraw everything
     */
    function withdrawAllInternal(address account) internal {
        withdrawInternal(account, userDeposit[account].share);
    }

    /**
     * @notice Update reward for an account and send to steward
     */
    function harvestInternal(address account) internal {
        updateVaultRewardInternal();
        accumulateReward(account);
    }

    /**
     * @dev Update reward state for vault to current block
     */
    function updateVaultRewardInternal() internal {
        uint256 blockReward = _pendingBlockReward();
        lastRewardBlock = block.number;
        rewardIndex =  _newRewardIndex(blockReward);
        if (blockReward > 0) {
            emit DistributeReward(blockReward);
        }
    }

    /**
     * @notice Update pending reward for a user to current
     * @dev It's crucial for this function to update user rewardIndex because other functions rely on that
     * @param account The user to pay out
     */
    function accumulateReward(address account) internal {
        AccountReward storage user = userReward[account];
        uint256 pending = rewardIndex
            .sub(user.rewardIndex)
            .mul(userDeposit[account].share)
            .div(FRACTIONAL_SCALE);

        user.rewardIndex = rewardIndex;
        if (pending > 0) {
            _startVesting(account, pending);
            emit Harvest(account, pending);
        }
    }

    /**
     * @notice Send out reward to vesting
     */
    function _startVesting(address account, uint256 amount) internal {
        if (amount > 0) {
            rewardLocker.lock(rewardToken, account, amount);
        }
    }


    /***   Internal helpers   ***/

    /**
     * @dev Safe transfer function, just in case if rounding error causes vault to not have enough reward tokens
     * @param to_ The address to be transferred
     * @param amount_ The amount to be transferred
     * @return actual amount of reward transferred
     */
    function _safeRewardTransfer(address to_, uint256 amount_) internal returns (uint256) {
        uint256 curBalance = rewardToken.balanceOf(address(this));

        if (amount_ > curBalance) {
            rewardToken.safeTransfer(to_, curBalance);
            return curBalance;
        } else {
            rewardToken.safeTransfer(to_, amount_);
            return amount_;
        }
    }

    /**
     * @dev Transfer token with balance checking before and after to account for tokens with transfer fee
     * @param token The token to transfer
     * @param from_ The address to be transferred
     * @param amount_ The amount to be transferred
     * @return actual amount this contract received
     */
    function _checkedTransferFrom(IERC20 token, address from_, uint256 amount_) internal returns (uint256) {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from_, address(this), amount_);
        return token.balanceOf(address(this)).sub(balanceBefore);
    }

    /**
     * @dev Convert deposit amount to share considering current share value
     */
    function _amountToShare(uint256 amount) internal view returns (uint256) {
        // return totalDeposit == 0 ? amount : amount.mul(FRACTIONAL_SCALE).div(totalDeposit).mul(totalShare).div(FRACTIONAL_SCALE);
        return totalDeposit == 0 ? amount : totalShare.mul(amount).div(totalDeposit);
    }

    /**
     * @dev Convert share to asset amount considering current share value
     */
    function _shareToAmount(uint256 share) internal view returns (uint256) {
        // return totalShare == 0 ? share : share.mul(FRACTIONAL_SCALE).div(totalShare).mul(totalDeposit).div(FRACTIONAL_SCALE);
        return totalShare == 0 ? share : totalDeposit.mul(share).div(totalShare);
    }

    /**
     * @dev Calculate pending reward since last updated block
     */
    function _pendingBlockReward() internal view returns (uint256) {
        if (block.number <= lastRewardBlock || totalDeposit == 0) {
            return 0;
        } else {
            return block.number.sub(lastRewardBlock).mul(rewardPerBlock);
        }
    }

    /**
     * @dev Calculate new reward index with given reward amount
     * @param rewardAmount Amount of reward to be distributed
     */
    function _newRewardIndex(uint256 rewardAmount) internal view returns (uint256) {
        if (rewardAmount == 0 || totalShare == 0) {
            return rewardIndex;
        } else {
            return rewardAmount.mul(FRACTIONAL_SCALE).div(totalShare).add(rewardIndex);
        }
    }

    /**
     * @dev Heuristic to determine some insignificant amount
     */
    // function _isDust(IERC20 token, uint256 amount) internal view returns (bool) {
    //     uint8 decimals = token.decimals();
    //     if (decimals >= 11) {
    //         return amount <= (10 ** (decimals - 8));
    //     } else if (decimals >= 5) {
    //         return amount <= 100;
    //     } else {
    //         return amount <= 1;
    //     }
    // }


    /***   Administrative Functions   ***/

    /**
     * @dev Initialize vault assigned token pair
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
    ) public initializer onlyAdmin {
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        setRewardLocker(_rewardLocker);
        setRewardPerBlock(_blockReward);
    }

    /**
     * @notice Set reward given to whole vault per block
     * @param newRate new reward rate
     */
    function setRewardPerBlock(uint256 newRate) public onlyAdmin {
        updateVaultRewardInternal();
        uint256 oldRate = rewardPerBlock;
        rewardPerBlock = newRate;
        emit NewRewardRate(oldRate, rewardPerBlock);
    }

    /**
     * @notice Set new reward locker
     * @param newRewardLocker_ new reward locker
     */
    function setRewardLocker(address newRewardLocker_) public onlyAdmin {
        address oldRewardLocker = address(rewardLocker);
        rewardLocker = IRewardLocker(newRewardLocker_);
        emit NewRewardLocker(oldRewardLocker, address(rewardLocker));
    }

    /**
     * @notice Freeze vault interaction (deposit, withdraw, harvest). For emergency use.
     * @dev Also emit Pause(sender) event
     */
    function freezeVault() external onlyAdmin {
        _pause();
    }

    /**
     * @notice Resume normal operation
     * @dev Also emit Unpause(sender) event
     */
    function unfreezeVault() external onlyAdmin {
        _unpause();
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin.
     * @param token The address of the ERC-20 token to sweep
     */
    function _sweepToken(IERC20 token) external nonReentrant {
    	require(token != depositToken, "SweepToken: can not sweep deposit token");
        // Unauthorized sweeping of reward token may disrupt reward distribution
        require((token != rewardToken) || (_msgSender() == admin), "SweepToken: only admin can sweep reward token");

        token.safeTransfer(admin, token.balanceOf(address(this)));
    }
}
