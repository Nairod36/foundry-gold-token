// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/ILottery.sol";

/**
 * @title GoldToken
 * @notice ERC20 token pegged to the price of gold (1 token = 1 gram of gold).
 * Users can mint tokens by sending ETH (converted via Chainlink) and 
 * burn tokens to receive ETH based on the current price.
 * A 5% fee is applied to each operation (mint and burn):
 * - 50% of the fees are sent to the lottery contract (using Chainlink VRF).
 * - 50% to the administrative fee collection address.
 */
contract GoldenTokenUUPS is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    // Chainlink price feeds
    AggregatorV3Interface public goldFeed; // XAU/USD price feed
    AggregatorV3Interface public ethFeed;  // ETH/USD price feed

    // Decimal constants
    uint256 public constant ETH_DECIMALS = 1e18;         
    uint256 public constant TOKEN_DECIMALS = 1e18;      

    // Mint ratio: 1 token per gram of gold
    uint256 public constant MINT_RATIO = 1;

    // Fee percentage applied to operations (5%)
    uint256 public constant FEE_PERCENTAGE = 5;

    // Lottery contract address (50% of the fees)
    ILottery public lotteryContract;
    // Administrative fee collection address (50% of the fees)
    address public adminFeeCollector;

    // Events
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);

    /// The constructor must be disabled to use the UUPS pattern, which requires the initializer modifier.
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract (replaces the constructor for UUPS).
     * @param _goldFeed Chainlink feed address for gold (XAU/USD).
     * @param _ethFeed Chainlink feed address for ETH (ETH/USD).
     * @param _lottery Address of the lottery contract.
     * @param _adminFeeCollector Address for collecting administrative fees.
     */
    function initialize(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed,
        ILottery _lottery,
        address _adminFeeCollector
    ) public initializer {
        require(address(_goldFeed) != address(0), "Invalid gold feed address");
        require(address(_ethFeed) != address(0), "Invalid ETH feed address");
        require(address(_lottery) != address(0), "Invalid lottery address");
        require(_adminFeeCollector != address(0), "Invalid admin fee collector address");

        __ERC20_init("GoldEth", "ETGLD");
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        goldFeed = _goldFeed;
        ethFeed = _ethFeed;
        lotteryContract = _lottery;
        adminFeeCollector = _adminFeeCollector;
    }

    /**
     * @notice Required function to authorize contract upgrades.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Allows updating the price feeds (useful for testing).
     */
    function setPriceFeeds(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed
    ) external onlyOwner {
        require(address(_goldFeed) != address(0), "Invalid gold feed address");
        require(address(_ethFeed) != address(0), "Invalid ETH feed address");
        goldFeed = _goldFeed;
        ethFeed = _ethFeed;
        emit PriceFeedsUpdated(address(_goldFeed), address(_ethFeed));
    }

    /**
     * @notice Retrieves the current gold price from Chainlink (8 decimals).
     */
    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = goldFeed.latestRoundData();
        require(answer > 0, "Invalid gold price");
        return uint256(answer);
    }

    /**
     * @notice Retrieves the current ETH price from Chainlink (8 decimals).
     */
    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = ethFeed.latestRoundData();
        require(answer > 0, "Invalid ETH price");
        return uint256(answer);
    }

    /**
     * @notice Estimates the number of tokens (before fees) obtained for a given ETH amount.
     * @param ethAmount Amount of ETH in wei used for minting.
     * @return tokenAmount Gross amount of tokens (18 decimals).
     */
    function previewMint(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        uint256 ethPrice = getEthPrice();
        uint256 goldPrice = getGoldPrice();
        uint256 usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS;
        tokenAmount = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice;
    }

    /**
     * @notice Allows users to mint tokens by sending ETH.
     * A 5% fee is applied:
     * - The requester receives the net amount.
     * - 50% of the fees are minted to the lottery contract.
     * - 50% of the fees are minted to the adminFeeCollector address.
     */
    function mint() public payable nonReentrant {
        require(msg.value > 0, "Must send ETH to mint tokens");
        uint256 grossTokenAmount = previewMint(msg.value);
        require(grossTokenAmount > 0, "Insufficient ETH for minting");

        uint256 feeTokens = (grossTokenAmount * FEE_PERCENTAGE) / 100;
        uint256 netTokenAmount = grossTokenAmount - feeTokens;

        _mint(msg.sender, netTokenAmount);
        _mint(address(lotteryContract), feeTokens / 2);
        _mint(adminFeeCollector, feeTokens / 2);

        emit Minted(msg.sender, msg.value, netTokenAmount);
    }

    /**
     * @notice Allows users to burn their tokens to receive ETH.
     * A 5% fee is deducted:
     * - The net amount (after fees) is converted to ETH based on current prices.
     * - 50% of the fees are minted to the lottery contract.
     * - 50% of the fees are minted to the adminFeeCollector address.
     * @param tokenAmount Total number of tokens to burn (including fees).
     */
    function burn(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient token balance");

        uint256 feeTokens = (tokenAmount * FEE_PERCENTAGE) / 100;
        uint256 netTokens = tokenAmount - feeTokens;

        uint256 ethPrice = getEthPrice();
        uint256 goldPrice = getGoldPrice();
        uint256 refundEth = (netTokens * goldPrice * ETH_DECIMALS) / (TOKEN_DECIMALS * MINT_RATIO * ethPrice);
        require(address(this).balance >= refundEth, "Contract balance insufficient for refund");

        _burn(msg.sender, tokenAmount);
        _mint(address(lotteryContract), feeTokens / 2);
        _mint(adminFeeCollector, feeTokens / 2);

        (bool sent, ) = msg.sender.call{value: refundEth}("");
        require(sent, "ETH transfer failed");

        emit Burned(msg.sender, tokenAmount, refundEth);
    }

    /**
     * @notice Allows the contract to receive ETH (e.g., during minting operations).
     */
    receive() external payable {}
}
