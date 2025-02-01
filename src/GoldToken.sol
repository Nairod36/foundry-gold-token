// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GoldToken is ERC20, Ownable {
    // Chainlink price feeds
    AggregatorV3Interface public priceFeed; // XAU/USD Chainlink price feed
    AggregatorV3Interface public priceEthUsdFeed; // ETH/USD Chainlink price feed

    // Constants for decimals
    uint256 public constant ETH_DECIMALS = 1e18;         // 18 décimales pour l'ETH (wei)
    uint256 public constant AGGREGATOR_DECIMALS = 1e8;     // 8 décimales pour les agrégateurs Chainlink
    uint256 public constant TOKEN_DECIMALS = 1e18;         // 18 décimales pour le token ERC20

    // Mint ratio
    uint256 public constant MINT_RATIO = 1;

    // Events
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 tokenAmount);
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

    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = priceFeed.latestRoundData();
        return uint256(answer);
    }

    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = priceEthUsdFeed.latestRoundData();
        return uint256(answer);
    }

    function previewMint(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        uint256 ethPrice = getEthPrice();
        uint256 goldPrice = getGoldPrice();
        uint256 usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS;
        tokenAmount = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice;
    }

    function mint() public payable {
        require(msg.value > 0, "You need to send some Ether");

        uint256 tokenAmount = previewMint(msg.value);

        require(tokenAmount > 0, "You need to send more Ether");
        _mint(msg.sender, tokenAmount);
    }
}