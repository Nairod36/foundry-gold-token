// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/ILottery.sol";

/**
 * @title GoldToken
 * @notice ERC20 dont la valeur est calquée sur le prix de l'or (1 token = 1 gramme d'or).
 * L'utilisateur peut minter des tokens en envoyant de l'ETH (conversion via Chainlink) et
 * brûler ses tokens pour obtenir de l'ETH selon le prix courant. À chaque opération (mint et burn),
 * un frais de 5% est appliqué : 50% de ces frais sont redirigés vers le contrat de loterie (qui devra utiliser Chainlink VRF)
 * et 50% vers l'adresse de collecte des frais.
 */
contract GoldToken is ERC20, Ownable, ReentrancyGuard {
    // Chainlink price feeds
    AggregatorV3Interface public goldFeed; // Feed XAU/USD
    AggregatorV3Interface public ethFeed;  // Feed ETH/USD

    // Constantes de décimales
    uint256 public constant ETH_DECIMALS = 1e18;         // 18 décimales pour l'ETH (wei)
    uint256 public constant TOKEN_DECIMALS = 1e18;         // 18 décimales pour le token ERC20

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
     * @notice Constructeur
     * @param _goldFeed Adresse du feed Chainlink pour l'or (XAU/USD)
     * @param _ethFeed Adresse du feed Chainlink pour l'ETH (ETH/USD)
     * @param _lottery Adresse du contrat de loterie
     * @param _adminFeeCollector Adresse de collecte des frais administratifs
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

    /**
     * @notice Permet de mettre à jour les feeds de prix (utile pour les tests)
     * @param _goldFeed Nouvelle adresse du feed Chainlink pour l'or
     * @param _ethFeed Nouvelle adresse du feed Chainlink pour l'ETH
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
     * @notice Récupère le prix courant de l'or via Chainlink
     * @return price Le prix de l'or (8 décimales)
     */
    function getGoldPrice() public view returns (uint256) {
        (, int256 answer, , , ) = goldFeed.latestRoundData();
        require(answer > 0, "Invalid gold price");
        return uint256(answer);
    }

    /**
     * @notice Récupère le prix courant de l'ETH via Chainlink
     * @return price Le prix de l'ETH (8 décimales)
     */
    function getEthPrice() public view returns (uint256) {
        (, int256 answer, , , ) = ethFeed.latestRoundData();
        require(answer > 0, "Invalid ETH price");
        return uint256(answer);
    }

    /**
     * @notice Permet d'estimer le nombre de tokens (avant frais) obtenus pour un montant donné d'ETH
     * @param ethAmount Montant d'ETH en wei utilisé pour le mint
     * @return tokenAmount Quantité brute de tokens (18 décimales)
     */
    function previewMint(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        uint256 ethPrice = getEthPrice(); // 8 décimales
        uint256 goldPrice = getGoldPrice(); // 8 décimales
        // Calcul de la valeur en USD : (ETH envoyé * prix de l'ETH) / 1e18 (pour ramener aux 8 décimales)
        uint256 usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS;
        // Conversion en tokens : (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice
        tokenAmount = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice;
    }

    /**
     * @notice Permet de minter des tokens en envoyant de l'ETH.
     * Une fois le calcul effectué, 5% des tokens sont déduits et répartis entre le contrat de loterie et l'adresse de collecte.
     * @dev Le frais est calculé sur le montant brut de tokens obtenus par conversion.
     */
    function mint() public payable nonReentrant {
        require(msg.value > 0, "Must send ETH to mint tokens");
        uint256 grossTokenAmount = previewMint(msg.value);
        require(grossTokenAmount > 0, "Insufficient ETH for minting");

        // Calcul du frais en tokens (5%)
        uint256 feeTokens = (grossTokenAmount * FEE_PERCENTAGE) / 100;
        // Calcul du montant net que l'utilisateur recevra
        uint256 netTokenAmount = grossTokenAmount - feeTokens;
        // Mint du montant brut vers l'utilisateur
        _mint(msg.sender, grossTokenAmount);
        // Répartition des frais : 50% pour l'admin et 50% pour la loterie
        uint256 feeForAdmin = feeTokens / 2;
        uint256 feeForLottery = feeTokens - feeForAdmin;
        _transfer(msg.sender, adminFeeCollector, feeForAdmin);
        _transfer(msg.sender, address(lotteryContract), feeForLottery);

        emit Minted(msg.sender, msg.value, netTokenAmount);
    }

    /**
     * @notice Permet de brûler des tokens pour récupérer de l'ETH.
     * 5% des tokens soumis à burn sont retenus comme frais, et la conversion se fait sur le montant net.
     * @param tokenAmount Quantité totale de tokens à brûler (incluant les frais)
     */
    function burn(uint256 tokenAmount) external nonReentrant {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient token balance");

        // Calcul des frais en tokens (5%)
        uint256 feeTokens = (tokenAmount * FEE_PERCENTAGE) / 100;
        // Montant net de tokens à convertir en ETH
        uint256 netTokens = tokenAmount - feeTokens;

        // Calcul du remboursement en ETH en se basant sur l'inverse de previewMint :
        // netTokens = (usdAmount * TOKEN_DECIMALS * MINT_RATIO) / goldPrice, où usdAmount = (ethAmount * ethPrice) / ETH_DECIMALS.
        // D'où : ethAmount = (netTokens * goldPrice * ETH_DECIMALS) / (TOKEN_DECIMALS * MINT_RATIO * ethPrice).
        uint256 ethPrice = getEthPrice();
        uint256 goldPrice = getGoldPrice();
        uint256 refundEth = (netTokens * goldPrice * ETH_DECIMALS) / (TOKEN_DECIMALS * MINT_RATIO * ethPrice);
        require(address(this).balance >= refundEth, "Contract balance insufficient for refund");

        // Répartition des frais : transfert de 50% des tokens de frais à l'admin et 50% à la loterie
        uint256 feeForAdmin = feeTokens / 2;
        uint256 feeForLottery = feeTokens - feeForAdmin;
        _transfer(msg.sender, adminFeeCollector, feeForAdmin);
        _transfer(msg.sender, address(lotteryContract), feeForLottery);
        // Brûlage du montant net de tokens
        _burn(msg.sender, netTokens);

        // Envoi de l'ETH correspondant au montant net
        (bool sent, ) = msg.sender.call{value: refundEth}("");
        require(sent, "ETH transfer failed");

        emit Burned(msg.sender, tokenAmount, refundEth);
    }

    // Permet au contrat de recevoir de l'ETH (lors des mint par exemple)
    receive() external payable {}
}