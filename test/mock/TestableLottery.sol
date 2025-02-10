// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/Lottery.sol";

/**
 * @title TestableLottery
 * @notice A test contract that extends `Lottery` to expose internal functions for testing.
 */
contract TestableLottery is Lottery {
    /**
     * @notice Constructor that initializes the `TestableLottery` contract.
     * @param _liquidityPool Address of the liquidity pool contract.
     * @param subscriptionId Chainlink VRF subscription ID.
     */
    constructor(address payable _liquidityPool, uint64 subscriptionId)
        Lottery(_liquidityPool, subscriptionId)
    {}

    /**
     * @notice Simulates the call to the VRF Coordinator.
     * @dev This function is used in tests to mock the VRF response.
     * @param requestId The request ID (determined via `vm.mockCall` in tests).
     * @param randomWords The list of random words (typically a single element) used to compute the ticket.
     */
    function testSimulateFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external {
        // Internal call to `fulfillRandomWords`.
        fulfillRandomWords(requestId, randomWords);
    }
}
