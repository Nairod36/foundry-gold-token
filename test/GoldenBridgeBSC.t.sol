// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "./mock/MockRouterClient.sol";
import "./mock/TestableGoldenBridgeBSC.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

error SafeERC20FailedOperation(address token);

contract GoldBridgeBSC_Test is Test {
    TestableGoldenBridgeBSC public bridgeBSC;
    MockRouterClient public mockRouter;
    MockERC20 public mockGoldToken;

    address public owner = address(0xABCD);
    address public user = address(0xBEEF);

    uint256 public constant INITIAL_GOLD_SUPPLY = 1000e18;
    uint256 public constant FEE = 10e18;

    event BridgeSent(
        bytes32 indexed messageId,
        uint64 indexed destinationChainSelector,
        address sender,
        uint256 amount,
        uint256 fees
    );
    
    function setUp() public {
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.deal(user, 100 ether);

        // Déployer le routeur et le token Gold (mock)
        mockRouter = new MockRouterClient(FEE);
        mockGoldToken = new MockERC20("Gold Token", "GLD", 18);

        // Mint des tokens Gold pour l'utilisateur sur BSC.
        mockGoldToken.mint(user, INITIAL_GOLD_SUPPLY);

        // Déployer le contrat via TestableGoldenBridgeBSC.
        bridgeBSC = new TestableGoldenBridgeBSC(
            address(mockRouter),
            address(mockGoldToken)
        );
    }

    // --- Tests du constructeur ---
    function testConstructorRevertsWithZeroRouter() public {
        vm.expectRevert();
        new TestableGoldenBridgeBSC(
            address(0),
            address(mockGoldToken)
        );
    }

    function testConstructorRevertsWithZeroGoldToken() public {
        vm.expectRevert("Invalid gold token address");
        new TestableGoldenBridgeBSC(
            address(mockRouter),
            address(0)
        );
    }

    // --- Tests de la fonction bridgeToEth() ---
    function testBridgeToEthSuccess() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        uint256 initialUserGold = mockGoldToken.balanceOf(user);
        uint256 initialBridgeGold = mockGoldToken.balanceOf(address(bridgeBSC));

        vm.prank(user);
        bool approved = mockGoldToken.approve(address(bridgeBSC), amount * 10);
        assertTrue(approved, "Approval should succeed");
        uint256 allowed = mockGoldToken.allowance(user, address(bridgeBSC));
        assertEq(allowed, amount * 10, "Allowance not set correctly");

        vm.prank(user);
        bytes32 messageId = bridgeBSC.bridgeToEth{value: FEE}(amount, recipient);

        assertEq(
            mockGoldToken.balanceOf(user),
            initialUserGold - amount,
            "Incorrect user Gold balance after bridge"
        );
        assertEq(
            mockGoldToken.balanceOf(address(bridgeBSC)),
            initialBridgeGold + amount,
            "Incorrect bridge Gold balance after bridge"
        );
        assertTrue(messageId != bytes32(0), "Message ID should not be zero");
    }

    function testBridgeToEthInsufficientGoldBalance() public {
        uint256 userGold = mockGoldToken.balanceOf(user);
        uint256 excessiveAmount = userGold + 1;
        address recipient = address(0xBEEF);

        vm.prank(user);
        mockGoldToken.approve(address(bridgeBSC), excessiveAmount);

        vm.prank(user);
        vm.expectRevert("Insufficient token balance");
        bridgeBSC.bridgeToEth{value: FEE}(excessiveAmount, recipient);
    }

    function testBridgeToEthApproveFails() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        vm.prank(user);
        bool approved = mockGoldToken.approve(address(bridgeBSC), amount * 10);
        assertTrue(approved, "Approval should succeed");
        mockGoldToken.setApproveReturnValue(false);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20FailedOperation.selector, address(mockGoldToken)));
        bridgeBSC.bridgeToEth{value: FEE}(amount, recipient);

        mockGoldToken.setApproveReturnValue(true);
    }

    function testBridgeToEthInsufficientEth() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        vm.prank(user);
        bool approved = mockGoldToken.approve(address(bridgeBSC), amount * 10);
        assertTrue(approved, "Approval should succeed");

        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(mockGoldToken),
            amount: amount
        });
        Client.EVM2AnyMessage memory evmMsg = Client.EVM2AnyMessage({
            receiver: abi.encode(recipient),
            data: abi.encode(amount),
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV2({
                gasLimit: 200_000,
                allowOutOfOrderExecution: true
            })),
            feeToken: address(0)
        });
        uint256 requiredFee = mockRouter.getFee(bridgeBSC.ETH_CHAIN_SELECTOR(), evmMsg);

        vm.prank(user);
        vm.expectRevert("Insufficient fee");
        bridgeBSC.bridgeToEth{value: requiredFee - 1}(amount, recipient);
    }

    // --- Tests pour la fonction _ccipReceive via testCcipReceive() ---
    function testCcipReceiveSuccess() public {
        uint256 amount = 50e18;
        mockGoldToken.mint(address(bridgeBSC), amount);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveSuccess"),
            sourceChainSelector: bridgeBSC.ETH_CHAIN_SELECTOR(),
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        uint256 initialUserGold = mockGoldToken.balanceOf(user);
        uint256 initialBridgeGold = mockGoldToken.balanceOf(address(bridgeBSC));

        bridgeBSC.testCcipReceive(message);

        assertEq(
            mockGoldToken.balanceOf(user),
            initialUserGold + amount,
            "User should receive tokens from bridge"
        );
        assertEq(
            mockGoldToken.balanceOf(address(bridgeBSC)),
            initialBridgeGold - amount,
            "Bridge balance should decrease by transferred amount"
        );
    }

    function testCcipReceiveWrongChain() public {
        uint256 amount = 50e18;
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveWrongChain"),
            sourceChainSelector: 999, // Mauvais sélecteur.
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.expectRevert("Message not from Ethereum");
        bridgeBSC.testCcipReceive(message);
    }

    function testCcipReceiveTransferFails() public {
        uint256 amount = 50e18;
        mockGoldToken.mint(address(bridgeBSC), amount);
        mockGoldToken.setTransferReturnValue(false);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveTransferFails"),
            sourceChainSelector: bridgeBSC.ETH_CHAIN_SELECTOR(),
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });
        vm.expectRevert(abi.encodeWithSelector(SafeERC20FailedOperation.selector, address(mockGoldToken)));
        bridgeBSC.testCcipReceive(message);
        mockGoldToken.setTransferReturnValue(true);
    }
}