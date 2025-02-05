// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../src/GoldBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract TestableGoldBridge is GoldBridge {
    constructor(
        address _router,
        address _linkToken,
        address _goldToken
    ) GoldBridge(_router, _linkToken, _goldToken) {}

    // Fonction publique permettant de tester _ccipReceive
    function testCcipReceive(Client.Any2EVMMessage calldata message) external {
        _ccipReceive(message);
    }
}