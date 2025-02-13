// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./Lottery.sol";

/**
 * @title GoldToken
 * @notice ERC20 token pegged to the price of gold (1 token = 1 gram of gold).
 * Users can mint tokens by sending ETH (conversion via Chainlink price feeds) and 
 * burn tokens to receive ETH at the current rate. A 5% fee is applied to mint and burn operations:
 * - 50% of the fee goes to the lottery contract (which uses Chainlink VRF).
 * - 50% goes to the admin fee collector address.
 */
contract GoldenToken is ERC20, Ownable, ReentrancyGuard {
    /// @notice Chainlink price feeds for XAU/USD (gold) and ETH/USD
    AggregatorV3Interface public goldFeed;
    AggregatorV3Interface public ethFeed;

    /// @notice Decimal precision for ETH (18 decimals)
    uint256 public constant ETH_DECIMALS = 1e18;
    /// @notice Decimal precision for the ERC20 token (18 decimals)
    uint256 public constant TOKEN_DECIMALS = 1e18;

    /// @notice Minting ratio: 1 token per gram of gold
    uint256 public constant MINT_RATIO = 1;

    /// @notice Fee percentage for mint and burn operations (5%)
    uint256 public constant FEE_PERCENTAGE = 5;

    /// @notice Address of the Lottery contract (receives 50% of fees)
    Lottery public lotteryContract;
    /// @notice Address that collects administrative fees (receives 50% of fees)
    address public adminFeeCollector;

    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);

    /**
     * @notice Constructor
     * @param _goldFeed Address of the Chainlink price feed for gold (XAU/USD).
     * @param _ethFeed Address of the Chainlink price feed for ETH (ETH/USD).
     * @param _lottery Address of the lottery contract.
     * @param _adminFeeCollector Address that collects administrative fees.
     */
    constructor(
        AggregatorV3Interface _goldFeed,
        AggregatorV3Interface _ethFeed,
        Lottery _lottery,
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

    /**
     * @notice Updates the price feed addresses (useful for testing).
     * @param _goldFeed New address of the Chainlink gold price feed.
     * @param _ethFeed New address of the Chainlink ETH price feed.
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
     * @notice Fetches the current gold price from Chainlink.
     * @return price Gold price (8 decimal places).
     */
    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = goldFeed.latestRoundData();
        require(answer > 0, "Invalid gold price");
        return uint256(answer);
    }

    /**
     * @notice Fetches the current ETH price from Chainlink.
     * @return price ETH price (8 decimal places).
     */
    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = ethFeed.latestRoundData();
        require(answer > 0, "Invalid ETH price");
        return uint256(answer);
    }

    /**
     * @notice Estimates the amount of tokens (before fees) obtained for a given ETH amount.
     * @param ethAmount Amount of ETH in wei used for minting.
     * @return tokenAmount Gross token amount (18 decimals).
     */
    function previewMint(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        uint256 ethPrice = getEthPrice(); // 8 decimals
        uint256 goldPrice = getGoldPrice(); // 8 decimals
        uint256 usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS;
        tokenAmount = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice;
    }

    /**
     * @notice Allows users to mint tokens by sending ETH.
     * A 5% fee is applied, and 50% of the fee is sent to the lottery contract,
     * while the other 50% is sent to the fee collector.
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
     * @notice Allows users to burn tokens to receive ETH.
     * A 5% fee is deducted, and the conversion is based on the net amount.
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
