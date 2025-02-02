// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/ILottery.sol";

contract GoldToken is ERC20, Ownable {
    // Chainlink price feeds
    AggregatorV3Interface public goldFeed; // XAU/USD Chainlink price feed
    AggregatorV3Interface public ethFeed; // ETH/USD Chainlink price feed

    // Constants for decimals
    uint256 public constant ETH_DECIMALS = 1e18;         // 18 décimales pour l'ETH (wei)
    uint256 public constant AGGREGATOR_DECIMALS = 1e8;     // 8 décimales pour les agrégateurs Chainlink
    uint256 public constant TOKEN_DECIMALS = 1e18;         // 18 décimales pour le token ERC20

    // Mint ratio
    uint256 public constant MINT_RATIO = 1;

    // Fee percentage
    uint256 public constant FEE_PERCENTAGE = 5;
    ILottery public lotteryContract;
    address public adminFeeCollector;

    // Events
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 tokenAmount);
    /**
     * @dev Constructor that gives msg.sender all of existing tokens.
     */
    constructor(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed,
        ILottery _lottery,
        address _adminFeeCollector
    )
        ERC20("GoldEth", "ETGLD")
        Ownable(msg.sender) 
    {
        require(address(_goldFeed) != address(0), "Invalid gold feed address");
        require(address(_ethFeed) != address(0), "Invalid ETH feed address");
        require(address(_lottery) != address(0), "Invalid lottery address");
        require(_adminFeeCollector != address(0), "Invalid admin fee collector address");

        goldFeed = _goldFeed;
        ethFeed = _ethFeed;
        lotteryContract = _lottery;
        adminFeeCollector = _adminFeeCollector;
    }

    // Function dedicated to set the price feeds for the contract, usefull for testing
    function setPriceFeeds(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed
    ) external onlyOwner {
        goldFeed = _goldFeed;
        ethFeed = _ethFeed;
    }

    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = goldFeed.latestRoundData();
        return uint256(answer);
    }

    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = ethFeed.latestRoundData();
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