// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockRouterClient
 * @notice Une implémentation mock du client Router Chainlink CCIP.
 * Ce contrat simule l'envoi de messages inter-chaînes et le calcul de frais pour les tests.
 */
contract MockRouterClient is IRouterClient {
    using SafeERC20 for IERC20;

    /// @notice Frais fixe pour tous les messages.
    uint256 public fee;
    /// @notice Identifiant de message fictif utilisé pour les tests.
    bytes32 public dummyMessageId;
    /// @notice Compteur du nombre de messages envoyés.
    uint256 public sendCount;

    /**
     * @notice Constructeur pour initialiser le mock du router.
     * @param _fee Le montant fixe de frais à utiliser pour tous les messages.
     */
    constructor(uint256 _fee) {
        fee = _fee;
    }

    /**
     * @dev Fonction utilisée à des fins de test.
     */
    function test() public {}

    /**
     * @notice Vérifie si une chaîne est supportée.
     * @return supported True si la chaîne est supportée, sinon false.
     */
    function isChainSupported(uint64 destChainSelector) external pure override returns (bool supported) {
        // Pour ce mock, toute valeur non nulle est considérée comme supportée.
        return destChainSelector != 0;
    }

    /**
     * @notice Renvoie le frais fixe pour n'importe quel message.
     * @return Le montant fixe de frais.
     */
    function getFee(
        uint64, /* destinationChainSelector */
        Client.EVM2AnyMessage memory /* message */
    ) external view override returns (uint256) {
        // Retourne simplement le frais prédéfini.
        return fee;
    }

    /**
     * @notice Simule l'envoi d'un message inter-chaînes et retourne un identifiant de message fictif.
     * @return Un identifiant de message fictif.
     */
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        // Si un feeToken est fourni (non zéro), effectue le transfert des frais.
        // Sinon, on suppose que les frais sont payés en ETH via msg.value.
        if (message.feeToken != address(0)) {
            IERC20 feeTokenInstance = IERC20(message.feeToken);
            feeTokenInstance.safeTransferFrom(msg.sender, address(this), fee);
        }
        
        // Pour les tokens à transférer, vérifier l'allowance.
        if (message.tokenAmounts.length > 0) {
            for (uint256 i = 0; i < message.tokenAmounts.length; i++) {
                IERC20 token = IERC20(message.tokenAmounts[i].token);
                require(
                    token.allowance(msg.sender, address(this)) >= message.tokenAmounts[i].amount,
                    "Insufficient token allowance"
                );
            }
        }
        
        sendCount++;
        // Calcul d'un identifiant fictif.
        dummyMessageId = keccak256(
            abi.encodePacked(sendCount, block.timestamp, destinationChainSelector, message.data)
        );
        return dummyMessageId;
    }
}