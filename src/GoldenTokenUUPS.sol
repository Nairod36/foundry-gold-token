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
 * @notice ERC20 dont la valeur est calquée sur le prix de l'or (1 token = 1 gramme d'or).
 * L'utilisateur peut minter des tokens en envoyant de l'ETH (conversion via Chainlink) et
 * brûler ses tokens pour obtenir de l'ETH selon le prix courant.
 * À chaque opération (mint et burn), un frais de 5% est appliqué :
 * - 50% des frais sont envoyés au contrat de loterie (utilisant Chainlink VRF)
 * - 50% à l'adresse de collecte des frais administratifs.
 */
contract GoldenTokenUUPS is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {

    // Chainlink price feeds
    AggregatorV3Interface public goldFeed; // Feed XAU/USD
    AggregatorV3Interface public ethFeed;  // Feed ETH/USD

    // Constantes de décimales
    uint256 public constant ETH_DECIMALS = 1e18;         
    uint256 public constant TOKEN_DECIMALS = 1e18;      

    // Ratio de mint : 1 token par gramme d'or
    uint256 public constant MINT_RATIO = 1;

    // Pourcentage de frais appliqué aux opérations (5%)
    uint256 public constant FEE_PERCENTAGE = 5;

    // Adresse du contrat de loterie (50% des frais)
    ILottery public lotteryContract;
    // Adresse de collecte des frais (50% des frais)
    address public adminFeeCollector;

    // Événements
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);

    /**
     * @notice Initialisation du contrat (remplace le constructeur pour UUPS)
     * @param _goldFeed Adresse du feed Chainlink pour l'or (XAU/USD)
     * @param _ethFeed Adresse du feed Chainlink pour l'ETH (ETH/USD)
     * @param _lottery Adresse du contrat de loterie
     * @param _adminFeeCollector Adresse de collecte des frais administratifs
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
     * @notice Fonction obligatoire pour autoriser les mises à jour du contrat
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Permet de mettre à jour les feeds de prix (utile pour les tests)
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
     * @notice Récupère le prix actuel de l'or depuis Chainlink (8 décimales)
     */
    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = goldFeed.latestRoundData();
        require(answer > 0, "Invalid gold price");
        return uint256(answer);
    }

    /**
     * @notice Récupère le prix actuel de l'ETH depuis Chainlink (8 décimales)
     */
    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = ethFeed.latestRoundData();
        require(answer > 0, "Invalid ETH price");
        return uint256(answer);
    }

    /**
     * @notice Estime le nombre de tokens (avant frais) obtenus pour un montant d'ETH donné.
     * @param ethAmount Montant d'ETH en wei utilisé pour le mint.
     * @return tokenAmount Montant brut de tokens (18 décimales).
     */
    function previewMint(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        uint256 ethPrice = getEthPrice();
        uint256 goldPrice = getGoldPrice();
        uint256 usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS;
        tokenAmount = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice;
    }

    /**
     * @notice Permet aux utilisateurs de minter des tokens en envoyant de l'ETH.
     * Un frais de 5% est appliqué :
     * - Le demandeur reçoit le montant net.
     * - 50% des frais sont _mintés au contrat de loterie.
     * - 50% des frais sont _mintés à l'adresse adminFeeCollector.
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
     * @notice Permet aux utilisateurs de brûler leurs tokens pour recevoir de l'ETH.
     * Un frais de 5% est prélevé :
     * - Le montant net (après frais) est converti en ETH selon les prix actuels.
     * - 50% des frais sont _mintés au contrat de loterie.
     * - 50% des frais sont _mintés à l'adresse adminFeeCollector.
     * @param tokenAmount Nombre total de tokens à brûler (frais inclus).
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
     * @notice Permet au contrat de recevoir de l'ETH (par exemple lors des opérations de mint).
     */
    receive() external payable {}
}