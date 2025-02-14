// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRouterClient} from "@chainlink/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GoldenBridge
 * @notice Bridge contract enabling the transfer of Gold tokens between Ethereum and BSC.
 * @dev Implements Chainlink CCIP for secure cross-chain messaging.
 */
contract GoldenBridge is CCIPReceiver, Ownable {
    IRouterClient public router;
    IERC20 public goldToken;

    /// @notice Chain selector for BSC (constant value provided by Chainlink)
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
     * @notice Initializes the contract with the required addresses.
     * @param _router Address of the CCIP router.
     * @param _goldToken Address of the Gold token.
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
     * @notice Sends Gold tokens to BSC.
     * @dev Fees are paid in ETH (via msg.value). The feeToken field is set to address(0).
     * @param amount Number of tokens to send.
     * @param receiver Recipient address on BSC.
     * @return messageId Unique identifier of the CCIP message.
     */
    function bridgeToBSC(
        uint256 amount,
        address receiver
    ) external payable returns (bytes32 messageId) {
        require(goldToken.balanceOf(msg.sender) >= amount, "Insufficient GLD balance");

        // Transfers Gold tokens from the sender to this contract.
        require(goldToken.transferFrom(msg.sender, address(this), amount), "Gold token transfer failed");
        
        // Approves the router to spend the Gold tokens.
        require(goldToken.approve(address(router), amount), "Gold token approval failed");

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(goldToken),
            amount: amount
        });

        // Here, feeToken is address(0), indicating that fees are paid in ETH.
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
        require(msg.value >= fees, "Insufficient ETH balance for fees");

        // Sends the CCIP message by transferring the ETH fees.
        messageId = router.ccipSend{value: fees}(BSC_CHAIN_SELECTOR, evm2AnyMessage);

        emit BridgeSent(messageId, BSC_CHAIN_SELECTOR, msg.sender, amount, fees);
        return messageId;
    }

    /**
     * @notice Handles the reception of CCIP messages.
     * @dev Internal function called by the CCIP router upon message reception.
     * @param any2EvmMessage Received message containing transfer information.
     */
    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    ) internal override {
        require(
            any2EvmMessage.sourceChainSelector == BSC_CHAIN_SELECTOR,
            "Message not from BSC"
        );

        address sender = abi.decode(any2EvmMessage.sender, (address));
        uint256 amount = abi.decode(any2EvmMessage.data, (uint256));

        require(
            goldToken.transfer(sender, amount),
            "Token transfer to recipient failed"
        );

        emit BridgeReceived(any2EvmMessage.messageId, any2EvmMessage.sourceChainSelector, sender, amount);
    }
}
