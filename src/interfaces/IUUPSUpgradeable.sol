// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
/** 
  * @title IUUPSUpgradeable
  * @notice Interface for UUPS upgradeable contracts.
  */
interface IUUPSUpgradeable {
    /**
     * @notice Checks if the caller is the current implementation.
     * @return True if the caller is the current implementation, false otherwise.
     */
    function isUUPSUpgradeable() external view returns (bool);
    
    /**
     * @notice Delegates the current call to an implementation contract.
     * @param newImplementation The address of the new implementation to which the call will be delegated.
     * @param data The call data.
     */
    function _authorizeUpgrade(address newImplementation, bytes calldata data) external;

    /**
     * @notice Upgrades the contract to a new implementation.
     * @param newImplementation The address of the new implementation.
     * @param data The call data.
     */
    function _upgradeTo(address newImplementation, bytes calldata data) external;
}