// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../../src/GoldenBridgeBSC.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

/**
 * @title TestableGoldBridgeBSC
 * @notice Contrat de test qui étend `GoldBridgeBSC` pour exposer des fonctions internes à des fins de test.
 */
contract TestableGoldenBridgeBSC is GoldBridgeBSC {
    /**
     * @notice Constructeur qui initialise le contrat TestableGoldBridgeBSC.
     * @param _router Adresse du routeur CCIP sur BSC.
     * @param _goldToken Adresse du token Gold sur BSC.
     */
    constructor(
        address _router,
        address _goldToken
    ) GoldBridgeBSC(_router, _goldToken) {}

    /**
     * @notice Expose la fonction interne _ccipReceive pour tester la réception de messages CCIP.
     * @param message Message inter-chaînes reçu via CCIP.
     */
    function testCcipReceive(Client.Any2EVMMessage calldata message) external {
        _ccipReceive(message);
    }
}