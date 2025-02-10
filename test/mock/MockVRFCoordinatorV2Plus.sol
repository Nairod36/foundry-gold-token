// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title MockVRFCoordinatorV2Plus
 * @notice This mock simulates the `requestRandomWords` function of the Chainlink VRF Coordinator.
 * It is used for testing purposes to track and emit random number request events.
 */
contract MockVRFCoordinatorV2Plus {
    /// @notice Counter for tracking request IDs.
    uint256 public requestIdCounter;

    /// @notice Event emitted when a random words request is made.
    event RandomWordsRequested(
        uint256 requestId,
        bytes32 keyHash,
        uint256 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        bytes extraArgs
    );

    /**
     * @dev A placeholder function for testing purposes.
     * This function is excluded from coverage reports.
     */
    function test() public {}

    /**
     * @notice Simulates a request for random words.
     * @param req The request structure containing parameters for the VRF request.
     * @return requestId The incremented request ID for tracking purposes.
     */
    function requestRandomWords(VRFV2PlusClient.RandomWordsRequest memory req)
        external
        returns (uint256 requestId)
    {
        requestIdCounter++;
        requestId = requestIdCounter;
        emit RandomWordsRequested(
            requestId,
            req.keyHash,
            req.subId,
            req.requestConfirmations,
            req.callbackGasLimit,
            req.numWords,
            req.extraArgs
        );
    }
}
