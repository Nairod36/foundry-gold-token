// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockRouterClient
 * @notice A mock implementation of the Chainlink CCIP Router Client.
 * This contract simulates cross-chain message sending and fee calculation for testing purposes.
 */
contract MockRouterClient is IRouterClient {
    /// @notice Fixed fee for all messages.
    uint256 public fee;
    /// @notice Dummy message ID used for testing.
    bytes32 public dummyMessageId;
    /// @notice Counter tracking the number of messages sent.
    uint256 public sendCount;

    /**
     * @notice Constructor to initialize the mock router client.
     * @param _fee The fixed fee amount to be used for all messages.
     */
    constructor(uint256 _fee) {
        fee = _fee;
    }

    /**
     * @dev Function used for testing purposes.
     * This function is excluded from coverage reports.
     */
    function test() public {}

    /**
     * @notice Checks if a chain is supported.
     * @param destChainSelector The selector for the destination chain.
     * @return supported True if the chain is supported, otherwise false.
     */
    function isChainSupported(
        uint64 destChainSelector
    ) external pure override returns (bool supported) {
        // For this mock, we consider that any non-zero value is supported.
        return destChainSelector != 0;
    }

    /**
     * @notice Returns the fixed fee for any message.
     * @param destinationChainSelector Selector for the destination chain (ignored in this mock).
     * @param message The message structure (ignored in this mock).
     * @return The fixed fee amount.
     */
    function getFee(
        uint64 /* destinationChainSelector */,
        Client.EVM2AnyMessage memory /* message */
    ) external view override returns (uint256) {
        // In this mock, we ignore destinationChainSelector and message and simply return the predefined fee.
        return fee;
    }

    /**
     * @notice Simulates sending a cross-chain message and returns a dummy message identifier.
     * @param destinationChainSelector The selector for the destination chain.
     * @param message The message structure containing the data and token transfers.
     * @return A dummy message ID.
     */
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        // Ensure that a fee token is provided.
        require(message.feeToken != address(0), "Fee token not provided");
        
        // Validate and transfer the LINK fee.
        IERC20 feeToken = IERC20(message.feeToken);
        require(
            feeToken.transferFrom(msg.sender, address(this), fee),
            "Fee transfer failed"
        );
        
        // For Gold tokens, we only verify the approval but do not transfer them since this is just a mock.
        if (message.tokenAmounts.length > 0) {
            for (uint256 i = 0; i < message.tokenAmounts.length; i++) {
                IERC20 token = IERC20(message.tokenAmounts[i].token);
                require(
                    token.allowance(msg.sender, address(this)) >= message.tokenAmounts[i].amount,
                    "Insufficient token allowance"
                );
            }
        }
        
        sendCount++;
        // Compute a dummy message ID using the counter, timestamp, destination, and a portion of the message data.
        dummyMessageId = keccak256(
            abi.encodePacked(sendCount, block.timestamp, destinationChainSelector, message.data)
        );
        return dummyMessageId;
    }
}
