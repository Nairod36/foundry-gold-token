pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import "../src/LotteryPool.sol";
import "./mock/TestableLottery.sol";
import "./mock/MockAggregator.sol";
import "./mock/MockERC20.sol";
import "./mock/MockRevertingReceiver.sol";

contract FullTest is Test {
    GoldToken public goldToken;
    TestableLottery public lottery;
    LotteryPool public pool;
    
    MockAggregator public mockGoldAggregator;
    MockAggregator public mockEthAggregator;
    MockERC20 public lotteryToken;

    address public admin = address(this);
    address public adminFeeCollector = address(0x456);
    address public user = address(0x123);
    address public user1 = address(0x1);
    address public user2 = address(0x2);
    
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);
    event LotteryStarted(uint256 timestamp);
    event PlayerEntered(address indexed player, uint256 amount);
    event WinnerChosen(address indexed winner, uint256 prize, uint256[3] targetTicket);
    event DiceRolled(address indexed roller, uint256 requestId);
    event LotteryNumbersDrawn(address indexed roller, uint256 requestId, uint256[3] numbers);
    
    function computeTicket(uint256 randomValue) public pure returns (uint256[3] memory ticket) {
        for (uint256 i = 0; i < 3; i++) {
            ticket[i] = (uint256(keccak256(abi.encode(randomValue, i))) % 50) + 1;
        }
    }
    
    function setUp() public {
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        mockGoldAggregator = new MockAggregator(2000, block.timestamp, 1, 18);
        mockEthAggregator  = new MockAggregator(1500, block.timestamp, 1, 18);
        pool = new LotteryPool();
        lottery = new TestableLottery(payable(address(pool)), 1);
        pool.transferOwnership(address(lottery));
        
        goldToken = new GoldToken(
            mockGoldAggregator,
            mockEthAggregator,
            lottery,
            adminFeeCollector
        );
    }

    function test() public {}
    
    
    function testPreviewMint() public view {
        uint256 expected = (1500 * 1e18) / 2000;
        uint256 preview = goldToken.previewMint(1 ether);
        assertEq(preview, expected, "Preview mint amount mismatch");
    }
    
    function testMint() public {
        lottery.startLottery();
        uint256 ethSent = 1 ether;
        uint256 gross = 750000000000000000;
        uint256 feeTokens = (gross * 5) / 100;
        uint256 net = gross - feeTokens;
        uint256 feeEach = feeTokens / 2;
        
        vm.deal(user, ethSent);
        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Minted(user, ethSent, net);
        goldToken.mint{value: ethSent}();
        
        assertEq(goldToken.balanceOf(user), net, "User token balance incorrect");
        assertEq(goldToken.balanceOf(adminFeeCollector), feeEach, "Admin fee balance incorrect");
        assertEq(goldToken.balanceOf(address(lottery)), feeEach, "Lottery fee balance incorrect");
        assertEq(goldToken.totalSupply(), gross, "Total supply must equal gross token amount");
    }
    
    
    function testLotteryReceiveRevertWhenNotStarted() public {
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert(bytes("Lottery not started"));
        (bool success, ) = address(lottery).call{value: 1 ether}("");
    }
    
    function testReceiveFromLiquidityPool() public {
        uint256 initialPlayers = lottery.getPlayers().length;
        vm.deal(address(pool), 1 ether);
        vm.prank(address(pool));
        (bool success, ) = address(lottery).call{value: 1 ether}("");
        assertTrue(success, "Call from liquidityPool should succeed");
        uint256 newPlayers = lottery.getPlayers().length;
        assertEq(newPlayers, initialPlayers, "Players list should not change when liquidityPool calls receive()");
    }
    
    function testLotteryParticipationAndTicket() public {
        lottery.startLottery();
        vm.deal(user1, 2 ether);
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        
        vm.prank(user1);
        (bool success, ) = address(lottery).call{value: 1 ether}("");
        assertTrue(success, "Participation should succeed");
        
        uint256 randomValue = 12345;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = randomValue;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randomWords);
        
        uint256[3] memory expectedTicket = computeTicket(randomValue);
        uint256[3] memory storedTicket = lottery.getLotteryResult(user1);
        for (uint256 i = 0; i < 3; i++) {
            assertEq(storedTicket[i], expectedTicket[i], "Ticket element mismatch");
        }
        
        address[] memory players = lottery.getPlayers();
        assertEq(players.length, 1, "Should have one participant");
        assertEq(players[0], user1, "User1 should be registered");
    }
    
    function testFinalizeLotteryUniqueWinner() public {
        lottery.startLottery();
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool s1, ) = address(lottery).call{value: 1 ether}("");
        require(s1, "User1 participation failed");
        uint256 randomValue1 = 10000;
        uint256[] memory randWords1 = new uint256[](1);
        randWords1[0] = randomValue1;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randWords1);
        uint256[3] memory ticket1 = computeTicket(randomValue1);
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(2))
        );
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool s2, ) = address(lottery).call{value: 1 ether}("");
        require(s2, "User2 participation failed");
        uint256 randomValue2 = 20000;
        uint256[] memory randWords2 = new uint256[](1);
        randWords2[0] = randomValue2;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(2, randWords2);
        uint256[3] memory ticket2 = computeTicket(randomValue2);
        
        uint256 targetRandom = 11000;
        uint256[] memory randWordsTarget = new uint256[](1);
        randWordsTarget[0] = targetRandom;
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(3))
        );
        vm.prank(admin);
        lottery.requestTargetTicket();
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(3, randWordsTarget);
        uint256[3] memory targetTicket = computeTicket(targetRandom);
        
        vm.prank(admin);
        lottery.finalizeLottery();
        
        uint256 dist1;
        uint256 dist2;
        for (uint256 i = 0; i < 3; i++) {
            dist1 += ticket1[i] > targetTicket[i] ? ticket1[i] - targetTicket[i] : targetTicket[i] - ticket1[i];
            dist2 += ticket2[i] > targetTicket[i] ? ticket2[i] - targetTicket[i] : targetTicket[i] - ticket2[i];
        }
        address expectedWinner = dist1 <= dist2 ? user1 : user2;
        assertEq(lottery.winner(), expectedWinner, "Unexpected winner");
        assertEq(pool.balance(), 0, "Liquidity pool should be empty after finalization");
    }
    
    function testFinalizeLotteryTie() public {
        lottery.startLottery();
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool s1, ) = address(lottery).call{value: 1 ether}("");
        require(s1, "User1 participation failed");
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(2))
        );
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool s2, ) = address(lottery).call{value: 1 ether}("");
        require(s2, "User2 participation failed");
        
        uint256 commonRandom = 12345;
        uint256[] memory randCommon = new uint256[](1);
        randCommon[0] = commonRandom;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randCommon);
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(2, randCommon);
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(3))
        );
        vm.prank(admin);
        lottery.requestTargetTicket();
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(3, randCommon);
        
        vm.prank(admin);
        lottery.finalizeLottery();
        
        address win = lottery.winner();
        bool valid = (win == user1 || win == user2);
        assertTrue(valid, "In a tie, winner must be either user1 or user2");
    }
    
    function testFinalizeLotteryRevertNotStarted() public {
        vm.prank(admin);
        vm.expectRevert("Lottery not started");
        lottery.finalizeLottery();
    }
    
    function testFinalizeLotteryRevertAlreadyEnded() public {
        lottery.startLottery();
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool s, ) = address(lottery).call{value: 1 ether}("");
        require(s, "Participation failed");
        uint256[] memory randWords = new uint256[](1);
        randWords[0] = 1000;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randWords);
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(2))
        );
        vm.prank(admin);
        lottery.requestTargetTicket();
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(2, randWords);
        
        vm.prank(admin);
        lottery.finalizeLottery();
        
        vm.prank(admin);
        vm.expectRevert("Lottery already ended");
        lottery.finalizeLottery();
    }
    
    function testFinalizeLotteryRevertNoPlayers() public {
        vm.prank(admin);
        lottery.startLottery();
        vm.prank(admin);
        vm.expectRevert("No players participated");
        lottery.finalizeLottery();
    }
    
    function testFinalizeLotteryRevertTargetNotFulfilled() public {
        vm.prank(admin);
        lottery.startLottery();
        vm.deal(user1, 1 ether);
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.prank(user1);
        (bool s, ) = address(lottery).call{value: 1 ether}("");
        require(s, "Participation failed");
        uint256[] memory randWords = new uint256[](1);
        randWords[0] = 5000;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randWords);
        
        vm.prank(admin);
        vm.expectRevert("Target ticket not fulfilled");
        lottery.finalizeLottery();
    }
    
    function testStartLotteryAlreadyStartedReverts() public {
        vm.prank(admin);
        lottery.startLottery();
        vm.prank(admin);
        vm.expectRevert("Lottery already started");
        lottery.startLottery();
    }
    
    function testGetPlayersList() public {
        vm.prank(admin);
        lottery.startLottery();
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        (bool s1, ) = address(lottery).call{value: 1 ether}("");
        require(s1, "User1 participation failed");
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(2))
        );
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool s2, ) = address(lottery).call{value: 1 ether}("");
        require(s2, "User2 participation failed");
        
        address[] memory players = lottery.getPlayers();
        assertEq(players.length, 2, "There should be 2 players");
        assertEq(players[0], user1, "First player should be user1");
        assertEq(players[1], user2, "Second player should be user2");
    }
    
    function testGetLotteryResultEmpty() public {
        uint256[3] memory result = lottery.getLotteryResult(user);
        assertEq(result[0], 0, "Expected zero ticket for element 0");
        assertEq(result[1], 0, "Expected zero ticket for element 1");
        assertEq(result[2], 0, "Expected zero ticket for element 2");
    }
    
    function testFinalizeLotteryPrizeTransferFails() public {
        MockRevertingReceiver rr = new MockRevertingReceiver();
        rr.setShouldRevert(false);
        
        lottery.startLottery();
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(1))
        );
        vm.deal(address(rr), 1 ether);
        vm.prank(address(rr));
        (bool success, ) = address(lottery).call{value: 1 ether}("");
        require(success, "RevertingReceiver participation failed");
        uint256[] memory randWords = new uint256[](1);
        randWords[0] = 7777;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(1, randWords);
        
        rr.setShouldRevert(true);
        
        vm.mockCall(
            address(0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B),
            bytes(""),
            abi.encode(uint256(2))
        );
        vm.prank(admin);
        lottery.requestTargetTicket();
        uint256[] memory targetWords = new uint256[](1);
        targetWords[0] = 8888;
        vm.prank(admin);
        lottery.testSimulateFulfillRandomWords(2, targetWords);
        
        vm.prank(admin);
        vm.expectRevert("Prize transfer failed");
        lottery.finalizeLottery();
    }
}