// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/GoldenBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title TestableGoldenBridge
 * @notice A test contract that extends `GoldenBridge` to expose internal functions for testing.
 */
contract TestableGoldenBridge is GoldenBridge {
    /**
     * @notice Constructor that initializes the TestableGoldenBridge contract.
     * @param _router Address of the Chainlink CCIP router.
     * @param _goldToken Address of the GoldToken contract.
     */
    constructor(
        address _router,
        address _goldToken
    ) GoldenBridge(_router, _goldToken) {}

    /**
     * @notice Fonction publique permettant de tester la réception des messages CCIP.
     * @param message Message inter-chaînes reçu via CCIP.
     */
    function testCcipReceive(Client.Any2EVMMessage calldata message) external {
        _ccipReceive(message);
    }
}