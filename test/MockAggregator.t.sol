// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mock/MockAggregator.sol";

contract MockAggregatorTest is Test {
    // Valeurs fixes pour le test
    int256 constant FIXED_ANSWER = 2000;
    uint256 constant FIXED_TIMESTAMP = 1000;
    uint256 constant FIXED_ROUND = 5;
    uint256 constant FIXED_DECIMALS = 18;

    MockAggregator aggregator;

    function setUp() public {
        // Déploiement du mock avec les valeurs fixes
        aggregator = new MockAggregator(FIXED_ANSWER, FIXED_TIMESTAMP, FIXED_ROUND, FIXED_DECIMALS);
    }

    function testLatestRoundData() public {
        // Appel de latestRoundData() et vérification de toutes les valeurs retournées
        (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.latestRoundData();

        assertEq(uint256(roundID), FIXED_ROUND, "roundID mismatch");
        assertEq(answer, FIXED_ANSWER, "answer mismatch");
        assertEq(startedAt, FIXED_TIMESTAMP, "startedAt mismatch");
        assertEq(updatedAt, FIXED_TIMESTAMP, "updatedAt mismatch");
        assertEq(uint256(answeredInRound), FIXED_ROUND, "answeredInRound mismatch");
    }

    function testGetRoundData() public {
        // Même si le paramètre _roundId est ignoré, on teste la fonction getRoundData()
        (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = aggregator.getRoundData(0); // La valeur passée n'est pas utilisée

        assertEq(uint256(roundID), FIXED_ROUND, "roundID mismatch");
        assertEq(answer, FIXED_ANSWER, "answer mismatch");
        assertEq(startedAt, FIXED_TIMESTAMP, "startedAt mismatch");
        assertEq(updatedAt, FIXED_TIMESTAMP, "updatedAt mismatch");
        assertEq(uint256(answeredInRound), FIXED_ROUND, "answeredInRound mismatch");
    }

    function testDecimals() public {
        // Vérifie que decimals() retourne la bonne valeur (casté en uint8)
        uint8 dec = aggregator.decimals();
        assertEq(dec, uint8(FIXED_DECIMALS), "Decimals mismatch");
    }

    function testDescription() public {
        // Vérifie que la description est bien "Mock Aggregator"
        string memory desc = aggregator.description();
        assertEq(desc, "Mock Aggregator", "Description mismatch");
    }

    function testVersion() public {
        // Vérifie que version() retourne 1
        uint256 ver = aggregator.version();
        assertEq(ver, 1, "Version mismatch");
    }
}
