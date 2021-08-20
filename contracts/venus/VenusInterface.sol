// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;
pragma abicoder v2;


abstract contract ComptrollerInterface {
    /// @notice Indicator that this is a Comptroller contract (for inspection)
    bool public constant isComptroller = true;

    /// @notice The Venus accrued but not yet transferred to each user
    mapping(address => uint) public venusAccrued;

    /**
     * @notice Claim all the Venus accrued by holder in all markets
     * @param holder The address to claim Venus for
     */
    function claimVenus(address holder) external virtual;

    /**
     * @notice Return the address of the XVS token
     * @return The address of XVS
     */
    function getXVSAddress() public view virtual returns (address);
}

abstract contract VBep20Storage {
    /**
     * @notice Underlying asset for this VToken
     */
    address public underlying;

    /**
     * @notice Contract which oversees inter-vToken operations
     */
    ComptrollerInterface public comptroller;
}

abstract contract VBep20Interface is VBep20Storage {
    /**
     * @notice Indicator that this is a VToken contract (for inspection)
     */
    bool public constant isVToken = true;

    function balanceOfUnderlying(address owner) external virtual returns (uint);
    function mint(uint mintAmount) external virtual returns (uint);
    function redeem(uint redeemTokens) external virtual returns (uint);
    function redeemUnderlying(uint redeemAmount) external virtual returns (uint);
    function borrow(uint borrowAmount) external virtual returns (uint);
}
