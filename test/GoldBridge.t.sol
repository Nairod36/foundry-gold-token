// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "./mock/MockRouterClient.sol";
import "./mock/TestableGoldBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract GoldBridgeTest is Test {
    TestableGoldBridge public goldBridge;
    MockRouterClient public mockRouter;
    MockERC20 public mockLinkToken;
    MockERC20 public mockGoldToken;

    // Adresses de test
    address public owner = address(0xABCD);
    address public user = address(0xBEEF);

    // Soldes initiaux pour les mocks (en wei)
    uint256 public constant INITIAL_GOLD_SUPPLY = 1000e18;
    uint256 public constant INITIAL_LINK_SUPPLY = 1000e18;
    uint256 public constant FEE = 10e18; // Fee fixé par le mockRouter

    // Événement attendu (défini dans GoldBridge)
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

        // Déploiement des mocks
        mockRouter = new MockRouterClient(FEE);
        mockLinkToken = new MockERC20("Chainlink", "LINK", 18);
        mockGoldToken = new MockERC20("Gold Token", "GLD", 18);

        // Attribution de tokens Gold au user
        mockGoldToken.mint(user, INITIAL_GOLD_SUPPLY);

        // Déploiement du contrat via TestableGoldBridge
        goldBridge = new TestableGoldBridge(
            address(mockRouter),
            address(mockLinkToken),
            address(mockGoldToken)
        );

        // Attribution de tokens LINK au contrat GoldBridge pour couvrir les frais CCIP
        mockLinkToken.mint(address(goldBridge), INITIAL_LINK_SUPPLY);
    }

    // --- Tests du constructeur ---
    function testConstructorRevertsWithZeroRouter() public {
        // Le revert attendu provient d'un custom error "InvalidRouter(address)"
        vm.expectRevert(abi.encodeWithSignature("InvalidRouter(address)", address(0)));
        new TestableGoldBridge(
            address(0),
            address(mockLinkToken),
            address(mockGoldToken)
        );
    }

    function testConstructorRevertsWithZeroLinkToken() public {
        vm.expectRevert("Invalid LINK token address");
        new TestableGoldBridge(
            address(mockRouter),
            address(0),
            address(mockGoldToken)
        );
    }

    function testConstructorRevertsWithZeroGoldToken() public {
        vm.expectRevert("Invalid gold token address");
        new TestableGoldBridge(
            address(mockRouter),
            address(mockLinkToken),
            address(0)
        );
    }

    // --- Tests de la fonction bridgeToBSC() ---
    function testBridgeToBSCInsufficientGoldBalance() public {
        address noBalance = address(0xDEAD);
        vm.prank(noBalance);
        vm.expectRevert("Solde GLD insuffisant");
        goldBridge.bridgeToBSC(1e18, user);
    }

    function testBridgeToBSCNoApproval() public {
        uint256 amount = 100e18;
        vm.prank(user);
        vm.expectRevert("Allowance exceeded");
        goldBridge.bridgeToBSC(amount, user);
    }

    function testBridgeToBSCInsufficientLinkBalance() public {
        uint256 amount = 100e18;
        // L'utilisateur approuve le transfert de ses tokens Gold
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);

        // Transférer les tokens LINK du contrat vers une autre adresse pour simuler un solde insuffisant
        vm.prank(address(goldBridge));
        mockLinkToken.transfer(owner, INITIAL_LINK_SUPPLY);

        vm.prank(user);
        vm.expectRevert("Solde LINK insuffisant pour les frais");
        goldBridge.bridgeToBSC(amount, user);
    }    

    // --- Tests de la fonction _ccipReceive() (via testCcipReceive) ---
    function testCcipReceiveSuccess() public {
        uint256 amount = 50e18;

        // Le contrat doit détenir des tokens Gold pour réaliser le transfert
        mockGoldToken.mint(address(goldBridge), amount);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32("testMessage"),
            sourceChainSelector: goldBridge.BSC_CHAIN_SELECTOR(),
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        uint256 initialUserGold = mockGoldToken.balanceOf(user);
        goldBridge.testCcipReceive(message);

        assertEq(
            mockGoldToken.balanceOf(user),
            initialUserGold + amount,
            "Le destinataire doit recevoir les tokens Gold"
        );
    }

    function testCcipReceiveFailsWrongChain() public {
        uint256 amount = 50e18;
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32("testMessage"),
            sourceChainSelector: 1234, // chaîne incorrecte
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert("Message non provenant de BSC");
        goldBridge.testCcipReceive(message);
    }

    function testCcipReceiveFailsWhenTransferFails() public {
        uint256 amount = 50e18;
        // Assurer que le contrat détient des tokens Gold
        mockGoldToken.mint(address(goldBridge), amount);
        // Forcer l'échec du transfert dans le mock via le setter
        mockGoldToken.setTransferReturnValue(false);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32("testMessage"),
            sourceChainSelector: goldBridge.BSC_CHAIN_SELECTOR(),
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert("Transfert de token vers le destinataire echoue");
        goldBridge.testCcipReceive(message);

        // Réinitialiser le flag pour ne pas impacter d'autres tests
        mockGoldToken.setTransferReturnValue(true);
    }

    // --- Test de détection de la chaîne ---
    function testChainIdDetection() public view {
        uint256 chainId = block.chainid;
        assert(chainId != 0);
    }
}