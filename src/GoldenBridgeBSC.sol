// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldBridgeBSC
 * @notice Contrat de pont sur Binance Smart Chain permettant de transférer des tokens Gold entre BSC et Ethereum.
 * @dev Implémente Chainlink CCIP pour la messagerie cross-chain sécurisée. Les frais sont payés en BNB (token natif).
 */
contract GoldBridgeBSC is CCIPReceiver, Ownable {

        function testA() public {} // forge coverage ignore-file

    IRouterClient public router;
    IERC20 public goldToken;

    /// @notice Sélecteur de chaîne pour Ethereum (par exemple, 1)
    uint64 public constant ETH_CHAIN_SELECTOR = 1;
    
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
     * @param _goldToken Adresse du token Gold (sur BSC).
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
     * @notice Permet à un utilisateur de bridger ses tokens Gold de BSC vers Ethereum.
     * @dev Les frais sont payés en BNB (via msg.value) et feeToken est address(0).
     * @param amount Montant de tokens à envoyer.
     * @param receiver Adresse du destinataire sur Ethereum.
     * @return messageId Identifiant unique du message CCIP.
     */
    function bridgeToEth(
        uint256 amount,
        address receiver
    ) external payable returns (bytes32 messageId) {
        require(goldToken.balanceOf(msg.sender) >= amount, "Insufficient token balance");

        require(goldToken.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        require(goldToken.approve(address(router), amount), "Token approval failed");

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(goldToken),
            amount: amount
        });
        
        // feeToken est address(0) pour indiquer que les frais sont payés en BNB.
        Client.EVM2AnyMessage memory evmMsg = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: abi.encode(amount),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV2({ gasLimit: 200_000, allowOutOfOrderExecution: true })
            ),
            feeToken: address(0)
        });
        
        uint256 fees = router.getFee(ETH_CHAIN_SELECTOR, evmMsg);
        require(msg.value >= fees, "Insufficient fee");

        messageId = router.ccipSend{value: fees}(ETH_CHAIN_SELECTOR, evmMsg);

        emit BridgeSent(messageId, ETH_CHAIN_SELECTOR, msg.sender, amount, fees);
        return messageId;
    }
    
    /**
     * @notice Gère la réception des messages CCIP (pour bridger des tokens depuis Ethereum vers BSC).
     * @dev Transfère les tokens Gold au destinataire indiqué dans le message.
     * @param any2EvmMessage Message CCIP reçu.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        require(
            any2EvmMessage.sourceChainSelector == ETH_CHAIN_SELECTOR,
            "Message not from Ethereum"
        );
        address sender = abi.decode(any2EvmMessage.sender, (address));
        uint256 amount = abi.decode(any2EvmMessage.data, (uint256));
        require(goldToken.transfer(sender, amount), "Transfer to recipient failed");
        emit BridgeReceived(any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sender, amount);
    }
}