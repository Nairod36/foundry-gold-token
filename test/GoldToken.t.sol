// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import { MockAggregator } from "./mock/MockAggregator.t.sol";

contract GoldTokenTest is Test {
    GoldToken goldToken;
    MockAggregator public mockAggregator;

    function setUp() public {
        // Deploy the contract with some values:
        // - price: 1000 ( = 1000 USD per ounce of gold )
        // - timestamp: block.timestamp
        // - round: 1 ( = latest round )
        // - decimals: 18
        mockAggregator = new MockAggregator(1000, block.timestamp, 1, 18);
        goldToken = new GoldToken();
    }

    function testGetPrice() public view {
        uint256 price = goldToken.getPrice(mockAggregator);
        assertEq(price, 1000, "Price should be 1000");
    }
}