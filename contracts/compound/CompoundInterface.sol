// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;



abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /// @notice The COMP accrued but not yet transferred to each user
    mapping(address => uint) public compAccrued;

    /**
     * @notice Claim all the comp accrued by holder in all markets
     * @param holder The address to claim COMP for
     */
    function claimComp(address holder) external virtual;

    /**
     * @notice Return the address of the COMP token
     * @return The address of COMP
     */
    function getCompAddress() public view virtual returns (address);
}

abstract contract CErc20Storage {
    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;

    /**
     * @notice Contract which oversees inter-cToken operations
     */
    ComptrollerInterface public comptroller;
}

abstract contract CErc20Interface is CErc20Storage {
    /**
     * @notice Indicator that this is a CToken contract (for inspection)
     */
    bool public constant isCToken = true;

    function balanceOfUnderlying(address owner) external virtual returns (uint);
    function mint(uint mintAmount) external virtual returns (uint);
    function redeem(uint redeemTokens) external virtual returns (uint);
    function redeemUnderlying(uint redeemAmount) external virtual returns (uint);
    function borrow(uint borrowAmount) external virtual returns (uint);
}
