// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldBridge
 * @notice Exemple de pont cross-chain via Chainlink CCIP pour le token Gold.
 */
contract GoldBridge is Ownable {
    IChainlinkCCIP public ccip;
    IERC20 public goldToken;

    // Mapping indiquant les chaînes autorisées pour le pont (ex : BSC)
    mapping(uint256 => bool) public authorizedChains;

    event BridgeSent(uint256 destinationChain, address indexed sender, uint256 amount);
    event BridgeReceived(uint256 sourceChain, address indexed receiver, uint256 amount);

    /**
     * @notice Constructeur de GoldBridge.
     * @param _ccip Adresse du contrat Chainlink CCIP.
     * @param _goldToken Adresse du token Gold (ERC20).
     */
    constructor(address _ccip, address _goldToken) Ownable(msg.sender) {
        require(_ccip != address(0), "Invalid CCIP address");
        require(_goldToken != address(0), "Invalid gold token address");
        ccip = IChainlinkCCIP(_ccip);
        goldToken = IERC20(_goldToken);
    }

    /**
     * @notice Autorise un réseau (chainId) pour l'utilisation du pont.
     * @param chainId Identifiant de la chaîne à autoriser.
     */
    function authorizeChain(uint256 chainId) external onlyOwner {
        authorizedChains[chainId] = true;
    }

    /**
     * @notice Envoie des tokens Gold depuis Ethereum vers un autre réseau via CCIP.
     * @param destinationChainId Identifiant de la chaîne de destination.
     * @param amount Montant de tokens à transférer.
     * @param receiver Adresse du destinataire sur la chaîne de destination.
     */
    function bridgeToChain(uint256 destinationChainId, uint256 amount, address receiver) external {
        require(authorizedChains[destinationChainId], "Chain not authorized");
        require(goldToken.balanceOf(msg.sender) >= amount, "Not enough GLD");

        // Transfert des tokens depuis l'expéditeur vers ce contrat (le pont)
        require(goldToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        // Préparation des tableaux pour l'appel CCIP
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = goldToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // Message optionnel
        bytes memory message = abi.encode("bridge GLD");

        // Appel à ccipSend pour initier le pont
        ccip.ccipSend(destinationChainId, message, tokens, amounts, receiver);

        emit BridgeSent(destinationChainId, msg.sender, amount);
    }

    /**
     * @notice Callback appelé par le réseau CCIP pour recevoir des tokens Gold depuis une autre chaîne.
     * @param sourceChainId Identifiant de la chaîne source.
     * @param tokens Tableau des tokens reçus (doit contenir uniquement goldToken).
     * @param amounts Tableau des montants reçus (doit contenir uniquement le montant correspondant).
     * @param sender Adresse de l'expéditeur sur la chaîne source (sera crédité sur cette chaîne).
     */
    function ccipReceive(
        uint256 sourceChainId,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address sender
    ) external {
        require(msg.sender == address(ccip), "Only CCIP can call");
        require(authorizedChains[sourceChainId], "Chain not authorized");
        require(tokens.length == 1, "Invalid tokens array length");
        require(amounts.length == 1, "Invalid amounts array length");
        require(tokens[0] == goldToken, "Invalid token");

        // Transfert des tokens du pont vers l'expéditeur (destinataire final)
        require(goldToken.transfer(sender, amounts[0]), "Transfer failed");

        emit BridgeReceived(sourceChainId, sender, amounts[0]);
    }
}

/**
 * @notice Interface indicative pour l'envoi via Chainlink CCIP.
 */
interface IChainlinkCCIP {
    function ccipSend(
        uint256 destinationChainSelector,
        bytes calldata message,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address receiver
    ) external payable;
}