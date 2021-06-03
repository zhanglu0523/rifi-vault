pragma solidity ^0.5.16;
import "./SafeBEP20.sol";
import "./IBEP20.sol";
import "./VaultProxy.sol";
import "./VaultStorage.sol";
import "./VaultErrorReporter.sol";

contract Vault is VaultStorage {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /// @notice Emitted on deposit
    event Deposit(address indexed user, uint256 amount);

    /// @notice Emitted on withrawal
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Emitted on claim
    event Claim(address indexed user, uint256 amount);

    constructor() public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "not admin");
        _;
    }

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "non reentrant");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    /**
     * @dev Initialize vault assigned token pair
     * @param _depositToken token that user would deposit into vault
     * @param _rewardToken token that user would receive as reward for deposit
     */
    function initialize(address _depositToken, address _rewardToken) public onlyAdmin {
        require(address(depositToken) == address(0), "initialized");
        require(address(rewardToken) == address(0), "initialized");

        depositToken = IBEP20(_depositToken);
        rewardToken = IBEP20(_rewardToken);

        _notEntered = true;
    }

    /**
     * @notice Deposit token to vault
     * @param _amount The amount to deposit to vault
     */
    function deposit(uint256 _amount) public nonReentrant {
        _deposit(_amount);
    }

    /**
     * @notice Internal function to handle Deposit
     * @param amount The amount to deposit to vault
     */
    function _deposit(uint256 amount) internal {
        UserInfo storage user = userInfo[msg.sender];

        updateVaultReward();
        // Must update reward balance before changing deposit
        accumulateReward(msg.sender);

        // Transfer in the amounts from user
        user.amount = user.amount.add(amount);
        totalDeposit = totalDeposit.add(amount);
        depositToken.safeTransferFrom(address(msg.sender), address(this), amount);
        emit Deposit(msg.sender, amount);
    }

    /**
     * @notice Withdraw token from vault
     * @param _amount The amount to withdraw from vault
     */
    function withdraw(uint256 _amount) public nonReentrant {
        _withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw everything and claim all reward
     */
    function withdrawAll() public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        _withdraw(msg.sender, user.amount);
        _claimReward();
    }

    /**
     * @notice Low level withdraw function
     * @param account The account to withdraw from vault
     * @param amount The amount to withdraw from vault
     */
    function _withdraw(address account, uint256 amount) internal {
        UserInfo storage user = userInfo[account];
        require(user.amount >= amount, "withdraw: exceed user balance");

        updateVaultReward();
        // Must update reward balance before changing deposit
        accumulateReward(account);

        user.amount = user.amount.sub(amount);
        totalDeposit = totalDeposit.sub(amount);
        depositToken.safeTransfer(address(account), amount);
        emit Withdraw(account, amount);
    }

    /**
     * @notice Claim all pending reward from vault
     */
    function claim() public nonReentrant {
        _claimReward();
    }

    /**
     * @notice Low level function to handle reward claim
     * @dev Must be protected from reentrancy by caller
     */
    function _claimReward() internal {
        updateVaultReward();
        accumulateReward(msg.sender);

        require(rewardToken.balanceOf(address(this)) > 0, "Claim: out of reward reserve");

        UserInfo storage user = userInfo[msg.sender];
        uint256 claimAmount = user.unclaimedReward;
        user.unclaimedReward = 0;

        uint256 sendAmount = safeRewardTransfer(msg.sender, claimAmount);
        user.unclaimedReward = claimAmount - sendAmount;
        emit Claim(msg.sender, sendAmount);
    }

    /**
     * @notice View function to see balance of an account
     * @param account The user to see unclaimed reward
     */
    function getBalance(address account) public view returns (uint256) {
        return userInfo[account].amount;
    }

    /**
     * @notice View function to see total unclaimed reward on frontend
     * @param account The user to see unclaimed reward
     */
    function getUnclaimedReward(address account) public view returns (uint256) {
        UserInfo storage user = userInfo[account];
        uint256 pending = calcNewRewardIndex().sub(user.rewardIndex).mul(user.amount).div(1e18);
        return pending.add(user.unclaimedReward);
    }

    /**
     * @notice Get reward pending since last update for a user
     * @param account The user to see pending reward
     */
    function getPendingReward(address account) internal view returns (uint256) {
        UserInfo storage user = userInfo[account];
        return rewardIndex.sub(user.rewardIndex).mul(user.amount).div(1e18);
    }

    /**
     * @notice Update pending reward for a user
     * @param account The user to pay out
     */
    function accumulateReward(address account) internal {
        uint256 pending = getPendingReward(account);

        UserInfo storage user = userInfo[account];
        user.unclaimedReward = user.unclaimedReward.add(pending);
        user.rewardIndex = rewardIndex;
    }

    /**
     * @dev Safe transfer function, just in case if rounding error causes pool to not have enough reward tokens
     * @param _to The address to be transferred
     * @param _amount The amount to be transferred
     * @return actual amount of reward transferred
     */
    function safeRewardTransfer(address _to, uint256 _amount) internal returns (uint256) {
        uint256 curBalance = rewardToken.balanceOf(address(this));

        if (_amount > curBalance) {
            rewardToken.safeTransfer(_to, curBalance);
            return curBalance;
        } else {
            rewardToken.safeTransfer(_to, _amount);
            return _amount;
        }
    }

    /**
     * @notice Update reward variables to be up-to-date
     */
    function updateVaultReward() internal {
        rewardIndex = calcNewRewardIndex();
        lastRewardBlock = block.number;
    }

    /**
     * @notice Calculate reward accumulated over blocks and/or additional endowment
     */
    function calcNewRewardIndex() internal view returns (uint256 index) {
        if (block.number <= lastRewardBlock || totalDeposit == 0) {
            return rewardIndex;
        }

        uint256 reward = block.number.sub(lastRewardBlock).mul(rewardPerBlock);
        return reward.mul(1e18).div(totalDeposit).add(rewardIndex);
    }

    /**
     * @notice Endow an amount of reward tokens to the vault, split equally among all current deposit shares
     * @param amount An optional extra amount of reward from caller account
     */
    function endowReward(uint256 amount) public nonReentrant {
        // Can't endow on empty vault
        require(totalDeposit > 0, "Endow: no deposit");

        uint256 balanceBefore = rewardToken.balanceOf(address(this));
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualEndowmentAmount = rewardToken.balanceOf(address(this)).sub(balanceBefore);
        rewardIndex = actualEndowmentAmount.mul(1e18).div(totalDeposit).add(rewardIndex);
    }

    /**
     * @dev Returns the address of the current admin
     */
    function getAdmin() public view returns (address) {
        return admin;
    }

    /*** Admin Functions ***/

    /**
     * @notice Set reward given to whole vault per block
     * @param newRate reward rate
     */
    function setRewardPerBlock(uint64 newRate) public onlyAdmin {
        rewardPerBlock = newRate;
    }

    /**
     * @dev Send all reward tokens in contract to admin
     */
    function drain() external onlyAdmin {
        safeRewardTransfer(admin, rewardToken.balanceOf(address(this)));
    }

    /**
     * @dev Become the new brain of proxy
     */
    function _become(VaultProxy proxy) public {
        require(msg.sender == proxy.admin(), "only proxy admin can change brains");
        require(proxy._acceptImplementation() == 0, "change not authorized");
    }
}
