// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldBridge
 * @author VotreNom
 * @notice Contrat de pont (bridge) permettant de transférer des tokens Gold entre Ethereum et BSC
 * @dev Implémente Chainlink CCIP pour la messagerie cross-chain sécurisée
 * @custom:security-contact security@votreprojet.com
 */
contract GoldBridge is CCIPReceiver, Ownable {
    IRouterClient public router;
    LinkTokenInterface public linkToken;
    IERC20 public goldToken;

    /// @notice Sélecteur de chaîne pour BSC (valeur constante fournie par Chainlink)
    uint64 public constant BSC_CHAIN_SELECTOR = 5009297550715157269;
    
    /**
     * @notice Émis lorsqu'un transfert de bridge est initié
     * @param messageId Identifiant unique du message CCIP
     * @param destinationChainSelector Identifiant de la chaîne de destination
     * @param sender Adresse de l'expéditeur
     * @param amount Montant de tokens envoyés
     * @param fees Frais payés en LINK
     */
    event BridgeSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address sender,
        uint256 amount,
        uint256 fees
    );

    /**
     * @notice Émis lorsqu'un transfert de bridge est reçu
     * @param messageId Identifiant unique du message CCIP
     * @param sourceChainSelector Identifiant de la chaîne source
     * @param sender Adresse de l'expéditeur sur la chaîne source
     * @param amount Montant de tokens reçus
     */
    event BridgeReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 amount
    );

    /**
     * @notice Initialise le contrat avec les adresses nécessaires
     * @dev Configure le routeur CCIP, le token LINK pour les frais et le token Gold
     * @param _router Adresse du routeur CCIP
     * @param _linkToken Adresse du token LINK
     * @param _goldToken Adresse du token Gold
     */
    constructor(
        address _router,
        address _linkToken,
        address _goldToken
    ) CCIPReceiver(_router) Ownable(msg.sender) {
        require(_router != address(0), "Invalid router address");
        require(_linkToken != address(0), "Invalid LINK token address");
        require(_goldToken != address(0), "Invalid gold token address");
        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_linkToken);
        goldToken = IERC20(_goldToken);
    }

    /**
     * @notice Envoie des tokens Gold vers BSC
     * @dev Utilise CCIP pour transférer les tokens de manière sécurisée
     * @param amount Montant de tokens à envoyer
     * @param receiver Adresse du destinataire sur BSC
     * @return messageId Identifiant unique du message CCIP
     */
    function bridgeToBSC(
        uint256 amount,
        address receiver
    ) external returns (bytes32 messageId) {
        require(goldToken.balanceOf(msg.sender) >= amount, "Solde GLD insuffisant");

        // Transfère les tokens Gold de l'expéditeur vers le contrat
        require(goldToken.transferFrom(msg.sender, address(this), amount), "Transfert de token Gold echoue");
        
        // Approuve le routeur pour dépenser les tokens Gold
        require(goldToken.approve(address(router), amount), "Approbation du token Gold echouee");

        // Prépare le tableau des montants de tokens
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(goldToken),
            amount: amount
        });

        // Prépare le message CCIP
        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({
                    gasLimit: 200_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(linkToken)
        });

        // Calcule les frais pour le transfert CCIP
        uint256 fees = router.getFee(BSC_CHAIN_SELECTOR, evm2AnyMessage);
        require(linkToken.balanceOf(address(this)) >= fees, "Solde LINK insuffisant pour les frais");

        // Approuve le routeur pour dépenser les LINK
        require(linkToken.approve(address(router), fees), "Approbation LINK echouee");

        // Envoie le message CCIP
        messageId = router.ccipSend(BSC_CHAIN_SELECTOR, evm2AnyMessage);

        emit BridgeSent(messageId, BSC_CHAIN_SELECTOR, msg.sender, amount, fees);
        return messageId;
    }

    /**
     * @notice Gère la réception des messages CCIP
     * @dev Fonction interne appelée par le routeur CCIP lors de la réception d'un message
     * @param any2EvmMessage Message reçu contenant les informations de transfert
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        require(
            any2EvmMessage.sourceChainSelector == BSC_CHAIN_SELECTOR,
            "Message non provenant de BSC"
        );

        address sender = abi.decode(any2EvmMessage.sender, (address));
        uint256 amount = abi.decode(any2EvmMessage.data, (uint256));

        // Gère les tokens reçus
        require(
            goldToken.transfer(sender, amount),
            "Transfert de token vers le destinataire echoue"
        );

        emit BridgeReceived(
            any2EvmMessage.messageId,
            any2EvmMessage.sourceChainSelector,
            sender,
            amount
        );
    }
}