// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockRouterClient is IRouterClient {
    uint256 public fee;
    bytes32 public dummyMessageId;
    uint256 public sendCount;

    constructor(uint256 _fee) {
        fee = _fee;
    }

    /// @notice Vérifie si une chaîne est supportée (ici, toute chaîne non nulle est supportée)
    function isChainSupported(
        uint64 destChainSelector
    ) external pure override returns (bool supported) {
        // Pour ce mock, nous considérons que toute valeur non nulle est supportée.
        return destChainSelector != 0;
    }

    /// @notice Retourne le fee fixé pour tout message.
    function getFee(
        uint64 /* destinationChainSelector */, /* name */
        Client.EVM2AnyMessage memory /* message */
    ) external view override returns (uint256) {
        // Ici, nous ignorons destinationChainSelector et message et retournons simplement le fee défini.
        return fee;
    }

    /// @notice Simule l'envoi d'un message cross-chain et retourne un identifiant de message.
    function ccipSend(
        uint64 destinationChainSelector,
        Client.EVM2AnyMessage calldata message
    ) external payable override returns (bytes32) {
        // Vérifier que le feeToken est bien fourni
        require(message.feeToken != address(0), "Fee token not provided");
        
        // Vérifier et transférer les frais LINK
        IERC20 feeToken = IERC20(message.feeToken);
        require(
            feeToken.transferFrom(msg.sender, address(this), fee),
            "Fee transfer failed"
        );
        
        // Pour les tokens Gold, on vérifie juste que le bridge a l'approbation
        // mais on ne les transfère pas réellement car c'est juste un mock
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
        // On calcule un identifiant de message dummy à partir du compteur, du timestamp, de la destination et d'une partie des données du message.
        dummyMessageId = keccak256(
            abi.encodePacked(sendCount, block.timestamp, destinationChainSelector, message.data)
        );
        return dummyMessageId;
    }
}