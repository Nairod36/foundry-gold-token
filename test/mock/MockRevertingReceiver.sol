// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title MockRevertingReceiver
 * @notice A mock contract that can be configured to reject incoming ETH transactions.
 * This is useful for testing scenarios where a contract refuses to accept ETH transfers.
 */
contract MockRevertingReceiver {
    /// @notice Determines whether the contract should revert on receiving ETH.
    bool public shouldRevert = true;

    /**
     * @dev A placeholder function for testing purposes.
     */
    function testA() public {}

    /**
     * @notice Updates the contract's behavior regarding ETH reception.
     * @param _value If true, the contract will revert on ETH transfers; otherwise, it will accept them.
     */
    function setShouldRevert(bool _value) external {
        shouldRevert = _value;
    }

    /**
     * @notice Fallback function that rejects ETH transfers if `shouldRevert` is set to true.
     */
    receive() external payable {
        if (shouldRevert) {
            revert("I reject ETH");
        }
    }

    /**
     * @notice Fallback function that rejects ETH transfers if `shouldRevert` is set to true.
     */
    fallback() external payable {
        if (shouldRevert) {
            revert("I reject ETH");
        }
    }
}
