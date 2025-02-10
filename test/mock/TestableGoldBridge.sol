// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../src/GoldBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title TestableGoldBridge
 * @notice A test contract that extends `GoldBridge` to expose internal functions for testing.
 */
contract TestableGoldBridge is GoldBridge {
    /**
     * @notice Constructor that initializes the TestableGoldBridge contract.
     * @param _router Address of the Chainlink CCIP router.
     * @param _linkToken Address of the LINK token contract.
     * @param _goldToken Address of the GoldToken contract.
     */
    constructor(
        address _router,
        address _linkToken,
        address _goldToken
    ) GoldBridge(_router, _linkToken, _goldToken) {}

    /**
     * @notice Public function to test the internal `_ccipReceive` function.
     * @param message The cross-chain message received via CCIP.
     */
    function testCcipReceive(Client.Any2EVMMessage calldata message) external {
        _ccipReceive(message);
    }
}
