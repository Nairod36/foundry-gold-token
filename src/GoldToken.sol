// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GoldToken is ERC20, Ownable {
    AggregatorV3Interface public priceFeed; // XAU/USD Chainlink price feed
    AggregatorV3Interface public priceEthUsdFeed; // ETH/USD Chainlink price feed

    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor()
        ERC20("GoldEth", "ETGLD")
        Ownable(msg.sender) 
    {
        priceFeed = AggregatorV3Interface(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6);
        priceEthUsdFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    }


    // Function dedicated to set the price feeds for the contract, usefull for testing
    function setPriceFeeds(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed
    ) external onlyOwner {
        priceFeed = _goldFeed;
        priceEthUsdFeed = _ethFeed;
    }

    function getGoldPrice(AggregatorV3Interface _priceFeed) public view returns (uint256) {
        (, int256 answer, , , ) = _priceFeed.latestRoundData();
        return uint256(answer);
    }

    function getEthPrice(AggregatorV3Interface _priceEthUsdFeed) public view returns (uint256) {
        (, int256 answer, , , ) = _priceEthUsdFeed.latestRoundData();
        return uint256(answer);
    }

    function mint() public payable {
        require(msg.value > 0, "You need to send some Ether");

        // get prices
        uint256 goldPrice = getGoldPrice(priceFeed);
        uint256 ethPrice = getEthPrice(priceEthUsdFeed);

        uint256 usdAmount = (msg.value * ethPrice) / 1e18; // 1e18 is the decimals of ETH
        uint256 tokenToMint = (usdAmount * 1e18) / goldPrice; // 1e18 is the decimals of the token

        require(tokenToMint > 0, "You need to send more Ether");
        _mint(msg.sender, tokenToMint);
    }
}