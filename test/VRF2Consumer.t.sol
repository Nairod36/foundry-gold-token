// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {VRF2Consumer} from "../src/VRF2Consumer.sol";
import {MockVRFCoordinatorV2Plus } from "./mock/MockVRFCoordinatorV2Plus.sol";

contract VRF2ConsumerTest is Test {
    VRF2Consumer consumer;
    MockVRFCoordinatorV2Plus mockCoordinator;
    address roller = 0x000000000000000000000000000000000000ABcD;
    uint64 subscriptionId = 1;

    address constant VRF_COORDINATOR_ADDRESS = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;

    function setUp() public {
        mockCoordinator = new MockVRFCoordinatorV2Plus();
        vm.etch(VRF_COORDINATOR_ADDRESS, address(mockCoordinator).code);

        // Déployer le contrat VRF2Consumer en utilisant le subscriptionId
        consumer = new VRF2Consumer(subscriptionId);
    }

    function testRoleDiceEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit VRF2Consumer.DiceRolled(roller, 1);
        uint256 reqId = consumer.roleDice(roller);
        assertEq(reqId, 1);
    }

    function testRoleDiceRevertsIfAlreadyRolled() public {
        consumer.roleDice(roller);
        vm.expectRevert("Already rolled");
        consumer.roleDice(roller);
    }

    function testGetLotteryResultBeforeFulfillment() public {
        uint256[3] memory ticket = consumer.getLotteryResult(roller);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(ticket[i], 0);
        }
    }

    function testFulfillRandomWords() public {
        uint256 reqId = consumer.roleDice(roller);

        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 123456; // valeur arbitraire

        vm.prank(VRF_COORDINATOR_ADDRESS);
        consumer.rawFulfillRandomWords(reqId, randomWords);

        uint256[3] memory ticket = consumer.getLotteryResult(roller);
        for (uint256 i = 0; i < 3; i++) {
            assertGt(ticket[i], 0);
            assertGe(ticket[i], 1);
            assertLe(ticket[i], 100);
        }
    }

    function testFulfillRandomWordsRevertsForUnknownRequest() public {
        uint256 fakeRequestId = 999;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 789;
        vm.prank(VRF_COORDINATOR_ADDRESS);
        vm.expectRevert("Unknown roller");
        consumer.rawFulfillRandomWords(fakeRequestId, randomWords);
    }

    function testFulfillRandomWordsRevertsIfAlreadyRolled() public {
        uint256 reqId = consumer.roleDice(roller);
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 111;
        vm.prank(VRF_COORDINATOR_ADDRESS);
        consumer.rawFulfillRandomWords(reqId, randomWords);
        vm.prank(VRF_COORDINATOR_ADDRESS);
        vm.expectRevert("Already rolled");
        consumer.rawFulfillRandomWords(reqId, randomWords);
    }
}
