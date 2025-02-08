// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title MockVRFCoordinatorV2Plus
 * @notice Ce mock simule la fonction requestRandomWords du VRF Coordinator.
 */
contract MockVRFCoordinatorV2Plus {
    uint256 public requestIdCounter;

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
     * @notice Simule la demande de randomWords.
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
