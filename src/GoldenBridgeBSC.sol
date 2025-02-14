// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldBridgeBSC
 * @notice Bridge contract on Binance Smart Chain for transferring Gold tokens between BSC and Ethereum.
 * @dev Implements Chainlink CCIP for secure cross-chain messaging. Fees are paid in BNB (native token).
 */
contract GoldBridgeBSC is CCIPReceiver, Ownable {

    IRouterClient public router;
    IERC20 public goldToken;

    /// @notice Chain selector for Ethereum (e.g., 1)
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
     * @notice Initializes the contract with the required addresses.
     * @param _router Address of the CCIP router.
     * @param _goldToken Address of the Gold token (on BSC).
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
     * @notice Allows a user to bridge their Gold tokens from BSC to Ethereum.
     * @dev Fees are paid in BNB (via msg.value), and feeToken is set to address(0).
     * @param amount Number of tokens to send.
     * @param receiver Recipient address on Ethereum.
     * @return messageId Unique identifier of the CCIP message.
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
        
        // feeToken is set to address(0) to indicate that fees are paid in BNB.
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
     * @notice Handles the reception of CCIP messages (to bridge tokens from Ethereum to BSC).
     * @dev Transfers Gold tokens to the recipient specified in the message.
     * @param any2EvmMessage Received CCIP message.
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
