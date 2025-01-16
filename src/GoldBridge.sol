// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/// @title GoldBridge
/// @notice Exemple de pont cross-chain via Chainlink CCIP
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface indicative pour CCIP Send
interface IChainlinkCCIP {
    function ccipSend(
        uint256 destinationChainSelector,
        bytes calldata message,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address receiver
    ) external payable;
}

contract GoldBridge is Ownable {
    IChainlinkCCIP public ccip;
    IERC20 public goldToken;

    // Mapping pour savoir si on autorise un certain chainSelector (ex: BSC)
    mapping(uint256 => bool) public authorizedChains;

    event BridgeSent(uint256 destinationChain, address indexed sender, uint256 amount);
    event BridgeReceived(uint256 sourceChain, address indexed receiver, uint256 amount);

    /**
     * @dev Le constructeur d'Ownable prend désormais un paramètre 'initialOwner'.
     * Ici, on met msg.sender comme propriétaire initial.
     */
    constructor(address _ccip, address _goldToken)
        Ownable(msg.sender) // <-- On passe msg.sender à Ownable
    {
        ccip = IChainlinkCCIP(_ccip);
        goldToken = IERC20(_goldToken);
    }

    function authorizeChain(uint256 chainId) external onlyOwner {
        authorizedChains[chainId] = true;
    }

    /// @notice Envoyer GLD depuis Ethereum vers un autre réseau
    function bridgeToChain(uint256 destinationChainId, uint256 amount, address receiver) external {
        require(authorizedChains[destinationChainId], "Chain not authorized");
        require(goldToken.balanceOf(msg.sender) >= amount, "Not enough GLD");

        // Transfer GLD to this contract
        goldToken.transferFrom(msg.sender, address(this), amount);

        // Appeler ccipSend
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = goldToken;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // On peut passer un message (par ex. "bridge GLD") si nécessaire
        bytes memory message = abi.encode("bridge GLD");

        ccip.ccipSend(
            destinationChainId,
            message,
            tokens,
            amounts,
            receiver
        );

        emit BridgeSent(destinationChainId, msg.sender, amount);
    }

    /// @notice Callback pour recevoir GLD depuis un autre réseau (via CCIP)
    function ccipReceive(
        uint256 sourceChainId,
        bytes calldata message,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address sender
    ) external {
        require(msg.sender == address(ccip), "Only CCIP can call");
        require(authorizedChains[sourceChainId], "Chain not authorized");

        // On vérifie que le token est bien goldToken
        require(tokens.length == 1 && tokens[0] == goldToken, "Invalid tokens array");
        
        // On crédite le receiver final qui doit être encodé dans 'message' ou 'sender'
        // Simplification : on considère que 'sender' est le destinataire
        goldToken.transfer(sender, amounts[0]);

        emit BridgeReceived(sourceChainId, sender, amounts[0]);
    }
}