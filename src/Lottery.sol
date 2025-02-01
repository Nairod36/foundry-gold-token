// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Lottery
/// @notice Contrat de loterie utilisant Chainlink VRF
/// @dev Simplifié, à adapter à vos besoins
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Interface VRFCoordinator
interface VRFCoordinatorV2Interface {
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 requestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId);
}

contract Lottery is Ownable {
    // Contrat VRFCoordinator
    VRFCoordinatorV2Interface public vrfCoordinator;
    
    // Paramètres VRF
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint16 public requestConfirmations;
    uint32 public callbackGasLimit;
    
    // Token GLD
    IERC20 public goldToken;
    
    // Liste des participants
    address[] public players;

    // Stockage du random request => pour callback
    mapping(uint256 => bool) public fulfilled;

    event PlayerEntered(address indexed player);
    event WinnerChosen(address indexed winner, uint256 amountWon);

    /**
     * @dev Le constructeur d’Ownable prend `address initialOwner`.
     * On fait du déployeur (msg.sender) le propriétaire par défaut.
     */
    constructor(
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subscriptionId,
        uint16 _requestConfirmations,
        uint32 _callbackGasLimit,
        address _goldToken
    )
        Ownable(msg.sender) // <-- L'adresse du déployeur devient le owner
    {
        vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subscriptionId;
        requestConfirmations = _requestConfirmations;
        callbackGasLimit = _callbackGasLimit;
        goldToken = IERC20(_goldToken);
    }

    /// @notice Permet à un joueur d'entrer dans la loterie
    function enter() external {
        // Ex: on peut définir un coût en GLD pour entrer
        // Simplification : pas de coût dans cet exemple
        players.push(msg.sender);
        emit PlayerEntered(msg.sender);
    }

    /// @notice Lancer la demande de random
    function startLottery() external onlyOwner {
        vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1
        );
    }

    /// @notice Callback du VRFCoordinator
    /// @dev Implémentation simplifiée (on n'utilise pas VRFConsumerBaseV2)
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal {
        require(!fulfilled[requestId], "Already fulfilled");
        fulfilled[requestId] = true;

        // Calcul du winner
        uint256 randomValue = randomWords[0];
        uint256 winnerIndex = randomValue % players.length;
        address winner = players[winnerIndex];

        // On envoie tout le solde GLD du contrat au gagnant
        uint256 balance = goldToken.balanceOf(address(this));
        if (balance > 0) {
            goldToken.transfer(winner, balance);
            emit WinnerChosen(winner, balance);
        }

        // Reset des joueurs
        delete players;
    }

    /**
     * @notice Méthode pour que le VRFCoordinator appelle fulfillRandomWords
     * @dev Dans la vraie vie, on utilise VRFConsumerBaseV2 qui a déjà un 
     * fulfillRandomWords, mais pour l'exemple, on le fait "manuellement".
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        require(msg.sender == address(vrfCoordinator), "Only VRFCoordinator");
        fulfillRandomWords(requestId, randomWords);
    }
}