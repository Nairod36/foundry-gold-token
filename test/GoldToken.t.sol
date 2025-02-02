// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import "../src/Lottery.sol";
import { MockAggregator } from "./mock/MockAggregator.t.sol";

contract GoldTokenTest is Test {
    GoldToken goldToken;
    Lottery lottery;    
    MockAggregator public mockGoldAggregator;
    MockAggregator public mockEthAggregator;

    address public  user = address(0x123);
    address public adminFeeCollector = address(0x456);

    function setUp() public {
        // Deploy the contract with some values:
        // - price: 1000 ( = 1000 USD per ounce of gold )
        // - timestamp: block.timestamp
        // - round: 1 ( = latest round, a round means a new price update )
        // - decimals: 18
        mockGoldAggregator = new MockAggregator(2000, block.timestamp, 1, 18);
        mockEthAggregator = new MockAggregator(1500, block.timestamp, 1, 18);

        lottery = new Lottery(IERC20(address(0x1))); // adresse dummy

        // Deploy the contract
        goldToken = new GoldToken(
            AggregatorV3Interface(address(mockGoldAggregator)),
            AggregatorV3Interface(address(mockEthAggregator)),
            ILottery(address(lottery)),
            adminFeeCollector
        );
        // Set the price feeds
        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(mockGoldAggregator, mockEthAggregator);
    }

    function testGetPrice() public view {
        uint256 price = goldToken.getGoldPrice();
        assertEq(price, 2000, "Gold Price should be 2000");
    }

    function testGetEthPrice() public view {
        uint256 price = goldToken.getEthPrice();
        assertEq(price, 1500, "ETH Price should be 1000");
    }

      function testPreviewMint() public view {
        uint256 ethAmount = 1e18; // 1 ETH
        uint256 expected = (1e18 * 1500) / 2000; 
        uint256 preview = goldToken.previewMint(ethAmount);
        assertEq(preview, expected, "Preview mint amount mismatch");
    }

    function testMint() public {

        uint256 ethToSent = 1e18; // 1 ETH
        uint256 expectedTokenToMint = (1e18 * 1500) / 2000; // 750 tokens

        vm.prank(user);
        vm.deal(user, ethToSent);

        goldToken.mint{value: ethToSent}();
        uint256 balance = goldToken.balanceOf(user);
         
        assertEq(balance / 1e18, expectedTokenToMint / 1e18, "User should have 750 tokens");
    }
}