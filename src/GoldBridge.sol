// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldBridge
 * @notice Contrat de pont (bridge) permettant de transférer des tokens Gold entre Ethereum et BSC.
 * @dev Implémente Chainlink CCIP pour la messagerie cross-chain sécurisée. Les frais sont payés en ETH (token natif).
 */
contract GoldenBridge is CCIPReceiver, Ownable {
    IRouterClient public router;
    IERC20 public goldToken;

    /// @notice Sélecteur de chaîne pour BSC (valeur constante fournie par Chainlink)
    uint64 public constant BSC_CHAIN_SELECTOR = 5009297550715157269;
    
    event BridgeSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address sender,
        uint256 amount,
        uint256 fees
    );

    event BridgeReceived(
        bytes32 indexed messageId,
        uint64 indexed sourceChainSelector,
        address sender,
        uint256 amount
    );

    /**
     * @notice Initialise le contrat avec les adresses nécessaires.
     * @param _router Adresse du routeur CCIP.
     * @param _goldToken Adresse du token Gold.
     */
    constructor(
        address _router,
        address _goldToken
    ) CCIPReceiver(_router) Ownable(msg.sender) {
        require(_router != address(0), "Invalid router address");
        require(_goldToken != address(0), "Invalid gold token address");
        router = IRouterClient(_router);
        goldToken = IERC20(_goldToken);
    }

    /**
     * @notice Envoie des tokens Gold vers BSC.
     * @dev Les frais sont payés en ETH (via msg.value). Le champ feeToken est fixé à address(0).
     * @param amount Montant de tokens à envoyer.
     * @param receiver Adresse du destinataire sur BSC.
     * @return messageId Identifiant unique du message CCIP.
     */
    function bridgeToBSC(
        uint256 amount,
        address receiver
    ) external payable returns (bytes32 messageId) {
        require(goldToken.balanceOf(msg.sender) >= amount, "Solde GLD insuffisant");

        // Transfère les tokens Gold de l'expéditeur vers ce contrat.
        require(goldToken.transferFrom(msg.sender, address(this), amount), "Transfert de token Gold echoue");
        
        // Approuve le routeur pour dépenser les tokens Gold.
        require(goldToken.approve(address(router), amount), "Approbation du token Gold echouee");

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(goldToken),
            amount: amount
        });

        // Ici, feeToken est address(0), indiquant que les frais sont payés en ETH.
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
            feeToken: address(0)
        });

        uint256 fees = router.getFee(BSC_CHAIN_SELECTOR, evm2AnyMessage);
        require(msg.value >= fees, "Solde ETH insuffisant pour les frais");

        // Envoie le message CCIP en transférant les ETH de frais.
        messageId = router.ccipSend{value: fees}(BSC_CHAIN_SELECTOR, evm2AnyMessage);

        emit BridgeSent(messageId, BSC_CHAIN_SELECTOR, msg.sender, amount, fees);
        return messageId;
    }

    /**
     * @notice Gère la réception des messages CCIP.
     * @dev Fonction interne appelée par le routeur CCIP lors de la réception d'un message.
     * @param any2EvmMessage Message reçu contenant les informations de transfert.
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

        require(
            goldToken.transfer(sender, amount),
            "Transfert de token vers le destinataire echoue"
        );

        emit BridgeReceived(any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sender, amount);
    }
}