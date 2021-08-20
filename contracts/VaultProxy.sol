// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;


import "./VaultStorage.sol";
import "./VaultErrorReporter.sol";


contract VaultProxy is VaultAdminStorage, VaultErrorReporter {

    /**
      * @notice Emitted when pendingVaultImplementation is changed
      */
    event NewPendingImplementation(address oldPendingImplementation, address newPendingImplementation);

    /**
      * @notice Emitted when pendingVaultImplementation is accepted, which means Rifi Vault implementation is updated
      */
    event NewImplementation(address oldImplementation, address newImplementation);

    /**
      * @notice Emitted when pendingAdmin is changed
      */
    event NewPendingAdmin(address oldPendingAdmin, address newPendingAdmin);

    /**
      * @notice Emitted when pendingAdmin is accepted, which means admin is updated
      */
    event NewAdmin(address oldAdmin, address newAdmin);


    constructor() {
        // Set admin to deployer
        _setAdmin(msg.sender);
    }


    /**
     * @dev Modifier used internally that will delegate the call to the implementation unless the sender is the admin.
     */
    modifier ifAdmin() {
        if (msg.sender == _getAdmin()) {
            _;
        } else {
            _delegate();
        }
    }


    /***   Public Functions   ***/

    /**
    * @notice Administrator for this contract
    */
    function getAdmin() public view returns (address) {
        return _getAdmin();
    }

    /**
    * @notice Pending administrator for this contract
    */
    function getPendingAdmin() public view returns (address) {
        return pendingAdmin;
    }

    /**
    * @notice Active brains of Rifi Vault
    */
    function getImplementation() public view returns (address) {
        return _getImplementation();
    }

    /**
    * @notice Pending brains of Rifi Vault
    */
    function getPendingImplementation() public view returns (address) {
        return pendingVaultImplementation;
    }


    /***   Admin Functions   ***/

    /**
      * @notice Begins transfer of admin rights. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @dev Admin function to begin change of admin. The newPendingAdmin must call `_acceptAdmin` to finalize the transfer.
      * @param newPendingAdmin New pending admin.
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPendingAdmin(address newPendingAdmin) public returns (uint) {
        // Check caller = admin
        if (msg.sender != _getAdmin()) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PENDING_ADMIN_OWNER_CHECK);
        }

        // Save current value, if any, for inclusion in log
        address oldPendingAdmin = pendingAdmin;
        // Store pendingAdmin with value newPendingAdmin
        pendingAdmin = newPendingAdmin;

        // Emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin)
        emit NewPendingAdmin(oldPendingAdmin, newPendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Accepts transfer of admin rights. msg.sender must be pendingAdmin
      * @dev Admin function for pending admin to accept role and update admin
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _acceptAdmin() public returns (uint) {
        // Check caller is pendingAdmin
        if (msg.sender != pendingAdmin) {
            return fail(Error.UNAUTHORIZED, FailureInfo.ACCEPT_ADMIN_PENDING_ADMIN_CHECK);
        }

        // Save current values for inclusion in log
        address oldAdmin = admin;
        address oldPendingAdmin = pendingAdmin;

        // Store admin with value pendingAdmin
        _setAdmin(pendingAdmin);
        // Clear the pending value
        pendingAdmin = address(0);

        emit NewAdmin(oldAdmin, _getAdmin());
        emit NewPendingAdmin(oldPendingAdmin, pendingAdmin);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Begins upgrading to new logic contract. The newPendingImplementation must call `_acceptImplementation` to finalize the transfer.
      * @param newPendingImplementation New pending implementation.
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _setPendingImplementation(address newPendingImplementation) public returns (uint) {
        if (msg.sender != _getAdmin()) {
            return fail(Error.UNAUTHORIZED, FailureInfo.SET_PENDING_IMPLEMENTATION_OWNER_CHECK);
        }

        address oldPendingImplementation = pendingVaultImplementation;
        pendingVaultImplementation = newPendingImplementation;

        emit NewPendingImplementation(oldPendingImplementation, pendingVaultImplementation);

        return uint(Error.NO_ERROR);
    }

    /**
      * @notice Accepts new implementation of Rifi Vault. msg.sender must be pendingImplementation
      * @dev Admin function for new implementation to accept it's role as implementation
      * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
      */
    function _acceptImplementation() public returns (uint) {
        // Check caller is pendingImplementation
        if (msg.sender != pendingVaultImplementation) {
            return fail(Error.UNAUTHORIZED, FailureInfo.ACCEPT_PENDING_IMPLEMENTATION_ADDRESS_CHECK);
        }

        // Save current values for inclusion in log
        address oldImplementation = vaultImplementation;
        address oldPendingImplementation = pendingVaultImplementation;

        // Store new implementation and clear pending
        _setImplementation(pendingVaultImplementation);
        pendingVaultImplementation = address(0);

        emit NewImplementation(oldImplementation, _getImplementation());
        emit NewPendingImplementation(oldPendingImplementation, pendingVaultImplementation);

        return uint(Error.NO_ERROR);
    }


    /**
     * @dev Delegates execution to an implementation contract.
     * It returns to the external caller whatever the implementation returns
     * or forwards reverts.
     */
    function _delegate() internal {
        // delegate all other functions to current implementation
        (bool success, ) = _getImplementation().delegatecall(msg.data);

        assembly {
            let free_mem_ptr := mload(0x40)
            returndatacopy(free_mem_ptr, 0, returndatasize())

            switch success
            case 0 { revert(free_mem_ptr, returndatasize()) }
            default { return(free_mem_ptr, returndatasize()) }
        }
    }

    /**
     * @dev Makes sure the admin cannot access the fallback function.
     */
    function _fallback() internal {
        // require(msg.sender != _getAdmin(), "TransparentUpgradeableProxy: admin cannot fallback to proxy target");
        _delegate();
    }

    /**
     * @dev Fallback function that delegates calls to implementation. Will run if call data is empty.
     */
    receive() external payable {
        _fallback();
    }

    /**
     * @dev Fallback function that delegates calls to implementation. Will run if no other function in the contract
     * matches the call data.
     */
    fallback() external payable {
        _fallback();
    }

    /***   Internal helpers   ***/

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return admin;
    }

    /**
     * @dev Set new admin.
     */
    function _setAdmin(address _newAdmin) internal {
        admin = _newAdmin;
    }

    /**
     * @dev Returns the current implementation.
     */
    function _getImplementation() internal view returns (address) {
        return vaultImplementation;
    }

    /**
     * @dev Set new implementation.
     */
    function _setImplementation(address _newImpl) internal {
        vaultImplementation = _newImpl;
    }
}

abstract contract VaultImplementation {
    /**
     * @dev Become the new brain of proxy
     */
    function _become(VaultProxy proxy) public virtual {
        require(msg.sender == proxy.getAdmin(), "_become: only proxy admin can change brains");
        require(proxy._acceptImplementation() == 0, "_become: change not authorized");
    }
}
