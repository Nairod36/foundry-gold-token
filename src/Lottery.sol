// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "./LotteryPool.sol";

/**
 * @title Lottery
 * @notice A smart contract for a lottery game utilizing Chainlink VRF for random number generation.
 */
contract Lottery is VRFConsumerBaseV2Plus {
    uint64 public SUBSCRIPTION_ID;
    address public vrfCoordinator = 0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B;
    bytes32 public keyHash = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;
    uint32 public callbackGasLimit = 40000;
    uint16 public requestConfirmations = 3;
    uint16 public numWords = 1;

    // Mapping VRF requests to user addresses
    mapping(uint256 => address) private s_rollers;
    struct LotteryResult {
        uint256[3] numbers;
    }
    mapping(address => LotteryResult) private s_results;
    mapping(address => bool) private s_requested;

    event DiceRolled(address indexed roller, uint256 requestId);
    event LotteryNumbersDrawn(address indexed roller, uint256 requestId, uint256[3] numbers);

    // Lottery state variables
    LotteryPool public liquidityPool;
    address[] public players;
    mapping(address => bool) public isParticipant;

    bool public lotteryStarted;
    bool public lotteryEnded;
    address public winner;
    uint256[3] public targetTicket;

    event LotteryStarted(uint256 timestamp);
    event PlayerEntered(address indexed player, uint256 amount);
    event WinnerChosen(address indexed winner, uint256 prize, uint256[3] targetTicket);

    /**
     * @notice Initializes the lottery contract.
     * @param _liquidityPool Address of the liquidity pool contract.
     * @param subscriptionId Chainlink VRF subscription ID.
     */
    constructor(
        address payable _liquidityPool,
        uint64 subscriptionId
    )
        VRFConsumerBaseV2Plus(vrfCoordinator)
    {
        require(_liquidityPool != address(0), "Invalid liquidity pool address");
        liquidityPool = LotteryPool(_liquidityPool);
        SUBSCRIPTION_ID = subscriptionId;
    }

    /**
     * @notice Requests random numbers from Chainlink VRF.
     * @param roller Address of the participant requesting the numbers.
     * @return requestId The request ID associated with the VRF request.
     */
    function rollDice(address roller) internal returns (uint256 requestId) {
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
                    VRFV2PlusClient.ExtraArgsV1({nativePayment: true})
                )
            })
        );
        s_rollers[requestId] = roller;
        emit DiceRolled(roller, requestId);
    }

    /**
     * @notice Converts a random value into a ticket with 3 numbers between 1 and 50.
     * @param randomValue The random number used to generate the ticket.
     * @return numbers The generated ticket numbers.
     */
    function _drawNumbers(uint256 randomValue) internal pure returns (uint256[3] memory numbers) {
        for (uint256 i = 0; i < 3; i++) {
            numbers[i] = (uint256(keccak256(abi.encode(randomValue, i))) % 50) + 1;
        }
    }

    /**
     * @notice Callback function triggered when Chainlink VRF fulfills a request.
     * @param requestId The request ID.
     * @param randomWords The random words returned by Chainlink VRF.
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
     * @notice Retrieves the lottery result (ticket) for a given address.
     * @param roller The address of the participant.
     * @return numbers The assigned lottery numbers.
     */
    function getLotteryResult(address roller) public view returns (uint256[3] memory numbers) {
        return s_results[roller].numbers;
    }

    /**
     * @notice Handles incoming ETH deposits and registers participants.
     */
    receive() external payable {
        if (msg.sender == address(liquidityPool)) {
            return;
        }

        require(lotteryStarted, "Lottery not started");
        require(msg.value > 0, "No ETH sent");
        require(!isParticipant[msg.sender], "Already entered");

        liquidityPool.deposit{value: msg.value}();

        isParticipant[msg.sender] = true;
        players.push(msg.sender);

        rollDice(msg.sender);

        emit PlayerEntered(msg.sender, msg.value);
    }

    /**
     * @notice Requests the target ticket to determine the winner.
     */
    function requestTargetTicket() external onlyOwner {
        require(getLotteryResult(address(this))[0] == 0, "Target ticket already requested");
        rollDice(address(this));
    }

    function _generateTargetTicket() internal view returns (uint256[3] memory) {
        return getLotteryResult(address(this));
    }

    /**
     * @notice Calculates the distance between two tickets.
     * @param ticket The player's ticket.
     * @param target The target ticket.
     * @return dist The computed distance.
     */
    function _ticketDistance(uint256[3] memory ticket, uint256[3] memory target) internal pure returns (uint256 dist) {
        for (uint256 i = 0; i < 3; i++) {
            uint256 a = ticket[i];
            uint256 b = target[i];
            dist += a > b ? a - b : b - a;
        }
    }

    /**
     * @notice Finalizes the lottery, selects the winner, and distributes the prize.
     */
    function finalizeLottery() external onlyOwner {
        require(lotteryStarted, "Lottery not started");
        require(!lotteryEnded, "Lottery already ended");
        require(players.length > 0, "No players participated");

        targetTicket = _generateTargetTicket();
        require(targetTicket[0] != 0, "Target ticket not fulfilled");

        uint256 minDistance = type(uint256).max;
        address[] memory candidates = new address[](players.length);
        uint256 candidateCount = 0;

        for (uint256 i = 0; i < players.length; i++) {
            uint256[3] memory playerTicket = getLotteryResult(players[i]);
            require(playerTicket[0] != 0, "Ticket not fulfilled for player");
            uint256 dist = _ticketDistance(playerTicket, targetTicket);
            if (dist < minDistance) {
                minDistance = dist;
                candidateCount = 0;
                candidates[candidateCount] = players[i];
                candidateCount = 1;
            } else if (dist == minDistance) {
                candidates[candidateCount] = players[i];
                candidateCount++;
            }
        }

        winner = candidateCount > 1
            ? candidates[uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao))) % candidateCount]
            : candidates[0];

        uint256 prize = liquidityPool.balance();
        liquidityPool.withdraw(prize);
        (bool sent, ) = winner.call{value: prize}("");
        require(sent, "Prize transfer failed");

        lotteryEnded = true;
        emit WinnerChosen(winner, prize, targetTicket);
    }

    function startLottery() external onlyOwner {
        require(!lotteryStarted, "Lottery already started");
        lotteryStarted = true;
        lotteryEnded = false;
        delete players;
        emit LotteryStarted(block.timestamp);
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }
}
