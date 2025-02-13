// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/GoldenBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title TestableGoldBridge
 * @notice Contrat de test qui étend `GoldBridge` pour exposer des fonctions internes à des fins de test.
 */
contract TestableGoldBridge is GoldenBridge {
    /**
     * @notice Constructeur qui initialise le TestableGoldBridge.
     * @param _router Adresse du routeur CCIP.
     * @param _goldToken Adresse du token Gold.
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