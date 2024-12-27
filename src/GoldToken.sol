// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title GoldToken
/// @author ...
/// @notice Un ERC20 indexé sur l'or, avec frais et loterie
/// @dev Utilise Chainlink Data Feeds XAU/USD et ETH/USD
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Interfaces pour les oracles Chainlink
interface AggregatorV3Interface {
    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

contract GoldToken is ERC20, Ownable {
    AggregatorV3Interface public priceFeedXAU; // XAU/USD
    AggregatorV3Interface public priceFeedETH; // ETH/USD

    // Adresse du contrat de loterie pour envoyer les fees
    address public lotteryContract;

    // Stockage total des fees accumulées
    uint256 public totalFees;

    // Événements
    event Minted(address indexed minter, uint256 amountInEth, uint256 tokensMinted, uint256 fees);
    event Burned(address indexed burner, uint256 tokensBurned, uint256 fees);

    constructor(
        address _priceFeedXAU,
        address _priceFeedETH
    ) ERC20("Gold Token", "GLD") {
        priceFeedXAU = AggregatorV3Interface(_priceFeedXAU);
        priceFeedETH = AggregatorV3Interface(_priceFeedETH);
    }

    /// @notice Définir l'adresse du contrat de loterie
    function setLotteryContract(address _lotteryContract) external onlyOwner {
        lotteryContract = _lotteryContract;
    }

    /// @notice Récupère la valeur du XAU/USD
    function getXAUPrice() public view returns (int256) {
        (, int256 price,,,) = priceFeedXAU.latestRoundData();
        return price; // En USD pour 1 once d'or (soit ~31,1035g)
    }

    /// @notice Récupère la valeur du ETH/USD
    function getETHPrice() public view returns (int256) {
        (, int256 price,,,) = priceFeedETH.latestRoundData();
        return price; // En USD pour 1 ETH
    }

    /// @notice Permet de minter des tokens en envoyant de l'ETH
    /// @dev 1 token = 1 gramme or
    /// @dev Frais de 5% sur le nombre total de tokens émis
    function mint() external payable {
        require(msg.value > 0, "No ETH sent");

        // 1) Récupérer le prix ETH/USD
        int256 ethPrice = getETHPrice(); 
        // 2) Récupérer le prix XAU/USD
        int256 xauPrice = getXAUPrice(); 

        // Conversion : 
        // Montant d'ETH en USD = msg.value * (ETH/USD)
        // Montant d'ETH en USD (en solidity) 
        // Il faut gérer les décimales ; hypothèse: aggregator = 8 decimales => price * 1e10 pour ETH
        uint256 ethUsd = (msg.value * uint256(ethPrice)) / 1e8;

        // Prix 1 once or en USD = xauPrice / 1e8
        // Convertir 1 once en gramme => 31.1035
        // => Prix 1 gramme = (xauPrice / 1e8) / 31.1035
        // => Donc nb grammes = (ethUsd / [prix_1_gramme])
        // Simplification possible dans un smart contract => on fait un ratio

        // NB : On reste simpliste ici, sans arrondir trop précisément.
        // xauPrice => 8 dec, on multiplie pour aligner
        uint256 xauPricePerGram = (uint256(xauPrice) * 1e10) / 311035; 
        // => 1 gramme = xauPricePerGram / 1e10 USD

        // Nombre de grammes = ethUsd / (xauPricePerGram / 1e10) = (ethUsd * 1e10) / xauPricePerGram
        uint256 grams = (ethUsd * 1e10) / xauPricePerGram;

        // Frais de 5%
        uint256 fee = (grams * 5) / 100; 
        uint256 mintedTokens = grams - fee;

        // Envoyer les frais accumulés
        totalFees += fee;

        // Mint pour l'utilisateur
        _mint(msg.sender, mintedTokens);
        
        emit Minted(msg.sender, msg.value, mintedTokens, fee);
    }

    /// @notice Brûler des tokens contre de l'ETH (optionnel, ou vs un stablecoin, etc.)
    /// @dev Frais de 5% des tokens brûlés
    function burn(uint256 _amount) external {
        require(balanceOf(msg.sender) >= _amount, "Not enough balance");

        // Frais
        uint256 fee = (_amount * 5) / 100;
        uint256 burnable = _amount - fee;

        // Brûle la portion burnable
        _burn(msg.sender, burnable);

        // Ajout du fee au totalFees
        totalFees += fee;
        // On brûle aussi la partie fee OU on la stocke pour la loterie
        _burn(msg.sender, fee);

        emit Burned(msg.sender, _amount, fee);

        // Ici, pour renvoyer l'équivalent en ETH, il faudrait gérer des réserves d'ETH dans le contrat
        // ou une autre logique. Pour l'exemple, on se limite à la destruction des tokens.
    }

    /// @notice Transférer les fonds accumulés au contrat de loterie
    function transferFeesToLottery() external onlyOwner {
        require(lotteryContract != address(0), "Lottery contract not set");
        uint256 _fees = totalFees;
        totalFees = 0;
        _transfer(address(this), lotteryContract, _fees);
    }
}