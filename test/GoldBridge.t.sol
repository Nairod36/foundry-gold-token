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

    // 1. Vérification du solde insuffisant de Gold
    function testBridgeToBSCInsufficientGoldBalance() public {
        address noBalance = address(0xDEAD);
        vm.prank(noBalance);
        vm.expectRevert("Solde GLD insuffisant");
        goldBridge.bridgeToBSC(1e18, user);
    }

    // 2. Vérification de l'absence d'approbation (transferFrom échoue à cause de l'allowance)
    function testBridgeToBSCNoApproval() public {
        uint256 amount = 100e18;
        vm.prank(user);
        vm.expectRevert("Allowance exceeded");
        goldBridge.bridgeToBSC(amount, user);
    }

    // 3. Solde LINK insuffisant pour payer les frais
    function testBridgeToBSCInsufficientLinkBalance() public {
        uint256 amount = 100e18;
        // L'utilisateur approuve le contrat pour le transfert de ses tokens Gold
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);

        // Transférer les tokens LINK du contrat vers une autre adresse pour simuler un solde insuffisant
        vm.prank(address(goldBridge));
        mockLinkToken.transfer(owner, INITIAL_LINK_SUPPLY);

        vm.prank(user);
        vm.expectRevert("Solde LINK insuffisant pour les frais");
        goldBridge.bridgeToBSC(amount, user);
    }

    // 4. Succès de bridgeToBSC (vérification des transferts et de l'événement émis)
    function testBridgeToBSCSuccess() public {
    uint256 amount = 100e18;
    address recipient = address(0xBEEF);
    
    // Initial balances
    uint256 initialUserGold = mockGoldToken.balanceOf(user);
    uint256 initialBridgeGold = mockGoldToken.balanceOf(address(goldBridge));
    uint256 initialBridgeLink = mockLinkToken.balanceOf(address(goldBridge));
    uint256 initialRouterLink = mockLinkToken.balanceOf(address(mockRouter));
    
    // Approve bridge to spend user's Gold tokens
    vm.prank(user);
    mockGoldToken.approve(address(goldBridge), amount);
    
    // Approve LINK pour le router directement depuis le bridge
    // Note: Ceci est nécessaire car le bridge doit approuver le router à dépenser ses LINK
    vm.prank(address(goldBridge));
    mockLinkToken.approve(address(mockRouter), FEE);
    
    // Execute bridge transfer
    vm.prank(user);
    bytes32 messageId = goldBridge.bridgeToBSC(amount, recipient);
    
    // Vérifier que l'ID du message correspond à celui stocké dans le mock
    assertEq(messageId, mockRouter.dummyMessageId(), "Message ID mismatch");
    
    // Verify Gold token transfers
    assertEq(
        mockGoldToken.balanceOf(user),
        initialUserGold - amount,
        "Incorrect user Gold balance after bridge"
    );
    assertEq(
        mockGoldToken.balanceOf(address(goldBridge)),
        initialBridgeGold + amount,
        "Incorrect bridge Gold balance after bridge"
    );
    
    // Verify LINK fee transfers
    assertEq(
        mockLinkToken.balanceOf(address(goldBridge)),
        initialBridgeLink - FEE,
        "Incorrect bridge LINK balance after fee payment"
    );
    assertEq(
        mockLinkToken.balanceOf(address(mockRouter)),
        initialRouterLink + FEE,
        "Incorrect router LINK balance after fee payment"
    );
    
    // Verify send count increased
    assertEq(mockRouter.sendCount(), 1, "Send count should be 1");
}

    // 5. Simuler l'échec de transferFrom dans le token Gold
    function testBridgeToBSCFailTransferFrom() public {
        uint256 amount = 100e18;
        vm.prank(user);
        // Approve normalement pour passer la vérification d'allowance
        mockGoldToken.approve(address(goldBridge), amount);
        // Forcer l'échec du transferFrom via le setter (à implémenter dans le mock)
        mockGoldToken.setTransferFromReturnValue(false);
        vm.prank(user);
        vm.expectRevert("Transfert de token Gold echoue");
        goldBridge.bridgeToBSC(amount, user);
        // Réinitialiser pour ne pas impacter d'autres tests
        mockGoldToken.setTransferFromReturnValue(true);
    }

    // 6. Simuler l'échec de l'approbation du token Gold
    function testBridgeToBSCFailGoldApprove() public {
        uint256 amount = 100e18;
        vm.prank(user);
        // Approve normalement pour permettre le transfertFrom
        mockGoldToken.approve(address(goldBridge), amount);
        // Forcer l'échec de approve sur le token Gold via le setter (à implémenter dans le mock)
        mockGoldToken.setApproveReturnValue(false);
        vm.prank(user);
        vm.expectRevert("Approbation du token Gold echouee");
        goldBridge.bridgeToBSC(amount, user);
        // Réinitialiser
        mockGoldToken.setApproveReturnValue(true);
    }

    // 7. Simuler l'échec de l'approbation du token LINK
    function testBridgeToBSCFailLinkApprove() public {
        uint256 amount = 100e18;
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);
        // Forcer l'échec de approve sur le token LINK via le setter (à implémenter dans le mock)
        mockLinkToken.setApproveReturnValue(false);
        vm.prank(user);
        vm.expectRevert("Approbation LINK echouee");
        goldBridge.bridgeToBSC(amount, user);
        // Réinitialiser
        mockLinkToken.setApproveReturnValue(true);
    }

    // --- Tests de la fonction _ccipReceive() (via testCcipReceive) ---

    // 8. Succès de _ccipReceive
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

    // 9. Rejet de _ccipReceive si le message provient d'une chaîne incorrecte
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

    // 10. Rejet de _ccipReceive si le transfert de token échoue
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
        // Réinitialiser
        mockGoldToken.setTransferReturnValue(true);
    }

    // --- Test de détection de la chaîne ---
    function testChainIdDetection() public view {
        uint256 chainId = block.chainid;
        assert(chainId != 0);
    }
}