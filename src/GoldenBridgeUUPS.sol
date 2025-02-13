// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title GoldenBridge
 * @notice Contrat de pont (bridge) permettant de transferer des tokens Gold entre Ethereum et BSC
 * @dev Implemente Chainlink CCIP pour la messagerie cross-chain securisee
 */
contract GoldenBridgeUUPS is CCIPReceiver, OwnableUpgradeable, UUPSUpgradeable {

        function testA() public {} // forge coverage ignore-file

    IRouterClient public router;
    LinkTokenInterface public linkToken;
    IERC20 public goldToken;

    /// @notice Selecteur de chaîne pour BSC (valeur constante fournie par Chainlink)
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
     * @notice Constructeur uniquement pour deploiement direct (hors proxy)
     * @param _router Adresse du routeur CCIP
     */
    constructor(address _router) CCIPReceiver(_router) {
        _disableInitializers(); // ✅ Empêche toute reinitialisation après un deploiement sans proxy
    }

    /**
     * @notice Initialisation du contrat UUPS (pour proxy)
     * @dev Configure le routeur CCIP, le token LINK et le token Gold
     * @param _router Adresse du routeur CCIP
     * @param _linkToken Adresse du token LINK
     * @param _goldToken Adresse du token Gold
     */
    function initialize(address _router, address _linkToken, address _goldToken) public initializer {
        require(_router != address(0), "Invalid router address");
        require(_linkToken != address(0), "Invalid LINK token address");
        require(_goldToken != address(0), "Invalid gold token address");

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        router = IRouterClient(_router);
        linkToken = LinkTokenInterface(_linkToken);
        goldToken = IERC20(_goldToken);
    }

    /**
     * @notice Autorisation de mise à jour (UUPS)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Envoie des tokens Gold vers BSC
     * @dev Utilise CCIP pour transferer les tokens de manière securisee
     * @param amount Montant de tokens à envoyer
     * @param receiver Adresse du destinataire sur BSC
     * @return messageId Identifiant unique du message CCIP
     */
    function bridgeToBSC(uint256 amount, address receiver) external returns (bytes32 messageId) {
        require(goldToken.balanceOf(msg.sender) >= amount, "Solde GLD insuffisant");
        require(goldToken.transferFrom(msg.sender, address(this), amount), "Transfert de token Gold echoue");
        require(goldToken.approve(address(router), amount), "Approbation du token Gold echouee");

        // ✅ Declaration correcte de `tokenAmounts`
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(goldToken),
            amount: amount
        });

        // ✅ Declaration correcte de `evm2AnyMessage`
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

        uint256 fees = router.getFee(BSC_CHAIN_SELECTOR, evm2AnyMessage);
        require(linkToken.balanceOf(address(this)) >= fees, "Solde LINK insuffisant pour les frais");
        require(linkToken.approve(address(router), fees), "Approbation LINK echouee");

        messageId = router.ccipSend(BSC_CHAIN_SELECTOR, evm2AnyMessage);
        emit BridgeSent(messageId, BSC_CHAIN_SELECTOR, msg.sender, amount, fees);
        return messageId;
    }

    /**
     * @notice Gère la reception des messages CCIP
     * @dev Fonction interne appelee par le routeur CCIP lors de la reception d'un message
     * @param any2EvmMessage Message reçu contenant les informations de transfert
     */
    function _ccipReceive(Client.Any2EVMMessage memory any2EvmMessage) internal override {
        require(any2EvmMessage.sourceChainSelector == BSC_CHAIN_SELECTOR, "Message non provenant de BSC");

        address sender = abi.decode(any2EvmMessage.sender, (address));
        uint256 amount = abi.decode(any2EvmMessage.data, (uint256));

        require(goldToken.transfer(sender, amount), "Transfert de token vers le destinataire echoue");
        emit BridgeReceived(any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sender, amount);
    }
}