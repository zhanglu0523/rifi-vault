// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;


import "../libraries/math/SafeMath.sol";
import "../libraries/token/IERC20.sol";
import "../libraries/token/SafeERC20.sol";
import "../libraries/security/ReentrancyGuard.sol";
import "../libraries/utils/Initializable.sol";
import "../libraries/utils/Context.sol";
import "../VaultProxy.sol";
import "../VaultStorage.sol";
import "./InterestRateModel.sol";
import "./LPConverter.sol";


contract FixedRateVault is VaultAdminStorage, VaultImplementation, Context, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /***   Constants   ***/


    /***   State variables   ***/

    IERC20 public depositToken;
    /// @dev amount of token deposited
    mapping(address => uint256) userDeposit;

    IERC20 public rewardToken;
    /// @dev point of time to lock / start accumulating interest
    uint128 public startTime;
    /// @dev time to full maturity
    uint128 public duration;
    IInterestRateModel public interestRateModel;
    ILPConverter public lpConverter;
    /// @dev amount for interest calculation
    mapping(address => uint256) public userIbNotes;


    /***   Events   ***/

    /// @notice Emitted on deposit
    event Deposit(address indexed user, uint256 amount, uint256 principal);

    /// @notice Emitted on withrawal
    event Withdraw(address indexed user, uint256 amount, uint256 interest);


    /***   Constructor   ***/

    constructor() ReentrancyGuard() {}


    /***   Modifiers   ***/

    /**
     * @dev Modifier to limit access of administration functions
     */
    modifier onlyAdmin() {
        require(_msgSender() == _getAdmin(), "not admin");
        _;
    }

    /**
     * @dev Returns the current admin.
     *      Copied from VaultProxy.
     */
    function _getAdmin() internal view returns (address) {
        return admin;
    }


    /***   Public functions   ***/

    /**
     * @notice Deposit token to vault
     * @param amount The amount to deposit to vault
     */
    function deposit(uint256 amount) public virtual nonReentrant {
        depositInternal(_msgSender(), amount, _msgSender());
    }

    /**
     * @notice Deposit token to vault
     * @param amount The amount to deposit to vault
     */
    function depositFor(address account, uint256 amount) public virtual nonReentrant {
        depositInternal(account, amount, _msgSender());
    }


    /**
     * @notice Withdraw all deposit and interest
     */
    function withdraw() external virtual nonReentrant {
        withdrawInternal(_msgSender());
    }

    /**
     * @notice Withdraw all deposit and interest
     * @dev add parameter for backward compatibility with older interface
     * @param amount Unused
     */
    function withdraw(uint256 amount) external virtual nonReentrant {
        amount;
        withdrawInternal(_msgSender());
    }

    /**
     * @notice Withdraw all deposit and interest
     * @dev function named for backward compatibility
     */
    function withdrawAll() external virtual nonReentrant {
        withdrawInternal(_msgSender());
    }

    /**
     * @notice View function to see balance of an account
     * @param account The user to see balance
     */
    function getBalance(address account) public view returns (uint256) {
        return userDeposit[account];
    }

    /**
     * @notice View function to see accumulated interest for an account (for backward compatibility)
     * @param account The user to see unclaimed reward
     */
    function getUnclaimedReward(address account) public view returns (uint256 reward) {
        (reward, ) = getCurrentInterest(account);
    }

    /**
     * @notice Return current interest rate and accumulated interest for an account
     * @param account The user to see interest and rate
     * @return interest = account accumulated interest (zero for empty account)
     *         rate = current interest rate (same for all accounts)
     */
    function getCurrentInterest(address account) public view returns (uint256 interest, uint256 rate) {
        if (block.timestamp < startTime) {
            rate = 0;
            interest = 0;
        } else {
            uint256 _depositDuration = block.timestamp.sub(uint256(startTime));
            if (_depositDuration > duration) {
                _depositDuration = duration;
            }
            uint256 _principal = userIbNotes[account];
            rate = interestRateModel.calculateRate(_depositDuration);
            interest = _principal.mul(rate).div(interestRateModel.PRECISION());
        }
    }


    /***   Internal machinery   ***/

    /**
     * @notice Internal function to handle deposit
     * @dev Must be protected from reentrancy by caller
     * @param account The account to deposit to vault
     * @param amount The amount to deposit to vault
     * @param spender The account to transfer token from (can be different to "account")
     */
    function depositInternal(address account, uint256 amount, address spender) internal virtual {
        require(block.timestamp < startTime, "Deposit: Deposit time is over");
        // Disallow multiple deposit
        require(userDeposit[account] == 0, "Deposit: May not deposit more on same account");

        // Transfer in the amount from user
        uint256 received = _checkedTransferFrom(depositToken, spender, amount);
        uint256 principal = lpConverter.convertLPToken(received, address(depositToken), address(rewardToken)).mul(2);

        // Update state
        userDeposit[account] = received;
        userIbNotes[account] = principal;

        emit Deposit(account, received, principal);
    }

    /**
     * @notice Low level withdraw function
     * @dev Must be protected from reentrancy by caller
     * @param account The account to withdraw
     */
    function withdrawInternal(address account) internal virtual {
        // Disallow partial withdrawal
        uint256 amount = userDeposit[account];

        (uint256 interest, ) = getCurrentInterest(account);

        require(interest <= rewardToken.balanceOf(address(this)), "Withdraw: Not enough reward available");

        // Update state
        userDeposit[account] = 0;
        userIbNotes[account] = 0;

        // Transfer tokens to user
        depositToken.safeTransfer(account, amount);
        if (interest > 0) {
            rewardToken.safeTransfer(account, interest);
        }

        emit Withdraw(account, amount, interest);
    }


    /***   Internal helpers   ***/

    /**
     * @dev Transfer token with balance checking before and after to account for tokens with transfer fee
     * @param token The token to transfer
     * @param from_ The address to be transferred
     * @param amount_ The amount to be transferred
     * @return Actual amount this contract received
     */
    function _checkedTransferFrom(IERC20 token, address from_, uint256 amount_) internal returns (uint256) {
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from_, address(this), amount_);
        return token.balanceOf(address(this)).sub(balanceBefore);
    }


    /***   Administrative Functions   ***/

    /**
     * @dev Initialize vault parameters
     * @param _depositToken token that user would deposit into vault
     * @param _rewardToken token that user would receive as reward for deposit
     * @param _startTime timestamp to start accumulating interest
     * @param _duration duration to accumulate interest
     * @param _converter LP token converter for calculating principal
     * @param _irModel model for calculating interest rate over time
     */
    function initializeVault(
        address _depositToken,
        address _rewardToken,
        uint128 _startTime,
        uint128 _duration,
        address _converter,
        address _irModel
    ) public virtual initializer onlyAdmin {
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        startTime = _startTime;
        duration = _duration;
        lpConverter = ILPConverter(_converter);
        interestRateModel = IInterestRateModel(_irModel);
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin.
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(IERC20 token) public onlyAdmin nonReentrant {
    	require(token != depositToken, "SweepToken: can not sweep deposit token");
        token.safeTransfer(admin, token.balanceOf(address(this)));
    }
}
