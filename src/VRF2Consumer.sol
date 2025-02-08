// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

contract VRF2Consumer is VRFConsumerBaseV2Plus {
    uint64 public SUBSCRIPTION_ID;

    address vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    uint32 public callbackGasLimit = 40000;
    uint16 public requestConfirmations = 3;
    uint16 public numWords = 1;
    
    mapping(uint256 => address) private s_rollers;
    
    struct LotteryResult {
        uint256[3] numbers;
    }
    mapping(address => LotteryResult) private s_results;
    mapping(address => bool) private s_requested;

    event DiceRolled(address indexed roller, uint256 requestId);
    event LotteryNumbersDrawn(address indexed roller, uint256 requestId, uint256[3] numbers);

    constructor(uint64 subscriptionId) VRFConsumerBaseV2Plus(vrfCoordinator) {
        SUBSCRIPTION_ID = subscriptionId;
    }

    /**
     * @notice Demande un tirage aléatoire auprès de Chainlink VRF pour un participant donné.
     * @param roller L'adresse du participant
     * @return requestId L'identifiant de la demande de randomisation
     */
    function roleDice(address roller) public onlyOwner returns (uint256 requestId) {
        require(!s_requested[roller], "Already rolled");
        s_requested[roller] = true;

        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: SUBSCRIPTION_ID,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    // nativePayment à true pour payer en ETH natif (ex. Sepolia) plutôt qu'en LINK
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );
        s_rollers[requestId] = roller;
        emit DiceRolled(roller, requestId);
    }

    /**
     * @notice Fonction interne qui transforme un nombre aléatoire en trois numéros entre 1 et 50.
     * @param randomValue Le nombre aléatoire retourné par Chainlink VRF.
     * @return numbers Un tableau contenant trois numéros compris entre 1 et 50.
     */
    function _drawNumbers(uint256 randomValue) internal pure returns (uint256[3] memory numbers) {
        for (uint256 i = 0; i < 3; i++) {
            numbers[i] = (uint256(keccak256(abi.encode(randomValue, i))) % 100) + 1;
        }
    }

    /**
     * @notice Callback appelée par le VRF Coordinator lorsque le nombre aléatoire est prêt.
     * @param requestId L'identifiant de la demande.
     * @param randomWords Le tableau contenant le (unique) mot aléatoire. calldata signifie que les données ne sont pas modifiables, à la différence de memory qui permet de les modifier.
     */
    function fulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) internal override {
        address roller = s_rollers[requestId];
        require(roller != address(0), "Unknown roller");
        require(s_results[roller].numbers[0] == 0, "Already rolled");

        uint256[3] memory numbers = _drawNumbers(randomWords[0]);
        s_results[roller] = LotteryResult(numbers);

        emit LotteryNumbersDrawn(roller, requestId, numbers);
    }

    /**
     * @notice Permet de consulter le résultat du tirage pour une adresse donnée.
     * @param roller L'adresse du participant.
     * @return numbers Le tableau contenant les trois numéros du loto.
     */
    function getLotteryResult(address roller) external view returns (uint256[3] memory numbers) {
        return s_results[roller].numbers;
    }
}
