// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import { MockAggregator } from "./mock/MockAggregator.t.sol";

contract GoldTokenTest is Test {
    GoldToken goldToken;
    MockAggregator public mockGoldAggregator;
    MockAggregator public mockEthAggregator;

    function setUp() public {
        // Deploy the contract with some values:
        // - price: 1000 ( = 1000 USD per ounce of gold )
        // - timestamp: block.timestamp
        // - round: 1 ( = latest round, a round means a new price update )
        // - decimals: 18
        mockGoldAggregator = new MockAggregator(1000, block.timestamp, 1, 18);
        mockEthAggregator = new MockAggregator(1500, block.timestamp, 1, 18);

        goldToken = new GoldToken();
    }

    function testGetPrice() public view {
        uint256 price = goldToken.getGoldPrice(mockGoldAggregator);
        assertEq(price, 1000, "Gold Price should be 1000");
    }

    function testGetEthPrice() public view {
        uint256 price = goldToken.getEthPrice(mockEthAggregator);
        assertEq(price, 1500, "ETH Price should be 1000");
    }
}