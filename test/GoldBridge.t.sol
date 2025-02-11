// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "./mock/MockERC20.sol";
import "./mock/MockRouterClient.sol";
import "./mock/TestableGoldBridge.sol";
import {Client} from "@chainlink/contracts/src/v0.8/ccip/libraries/Client.sol";

contract GoldBridgeTest is Test {
    TestableGoldBridge public goldBridge;
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

        // Approvisionner l'utilisateur en ETH pour payer les frais.
        vm.deal(user, 100 ether);

        // Déploiement des mocks.
        mockRouter = new MockRouterClient(FEE);
        mockGoldToken = new MockERC20("Gold Token", "GLD", 18);

        // Mint Gold tokens pour l'utilisateur.
        mockGoldToken.mint(user, INITIAL_GOLD_SUPPLY);
        
        // Déploiement du bridge en transmettant les adresses correctes :
        // - router : mockRouter
        // - goldToken : mockGoldToken
        goldBridge = new TestableGoldBridge(
            address(mockRouter),
            address(mockGoldToken)
        );
    }

    // --- Tests du constructeur ---
    
    function testConstructorRevertsWithZeroRouter() public {
        vm.expectRevert();
        new TestableGoldBridge(
            address(0),
            address(mockGoldToken)
        );
    }

    function testConstructorRevertsWithZeroGoldToken() public {
        vm.expectRevert("Invalid gold token address");
        new TestableGoldBridge(
            address(mockRouter),
            address(0)
        );
    }

    // --- Tests de la fonction bridgeToBSC() ---
    
    function testBridgeToBSCSuccess() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        uint256 initialUserGold = mockGoldToken.balanceOf(user);
        uint256 initialBridgeGold = mockGoldToken.balanceOf(address(goldBridge));

        // L'utilisateur approuve le bridge pour dépenser ses tokens Gold (approuve une quantité largement supérieure).
        vm.prank(user);
        bool approved = mockGoldToken.approve(address(goldBridge), amount * 10);
        assertTrue(approved, "Approval should succeed");
        uint256 allowed = mockGoldToken.allowance(user, address(goldBridge));
        assertEq(allowed, amount * 10, "Allowance not set correctly");

        // L'utilisateur appelle bridgeToBSC en fournissant les frais en ETH.
        vm.prank(user);
        bytes32 messageId = goldBridge.bridgeToBSC{value: FEE}(amount, recipient);

        // Vérifier que le solde de tokens Gold du user a diminué du montant transféré.
        assertEq(
            mockGoldToken.balanceOf(user),
            initialUserGold - amount,
            "Incorrect user Gold balance after bridge"
        );
        // Vérifier que le bridge détient désormais les tokens Gold transférés.
        assertEq(
            mockGoldToken.balanceOf(address(goldBridge)),
            initialBridgeGold + amount,
            "Incorrect bridge Gold balance after bridge"
        );
        // Vérifier que le messageId retourné n'est pas nul.
        assertTrue(messageId != bytes32(0), "Message ID should not be zero");
    }

    function testBridgeToBSCInsufficientGoldBalance() public {
        uint256 userGold = mockGoldToken.balanceOf(user);
        uint256 excessiveAmount = userGold + 1; // Plus que le solde du user.
        address recipient = address(0xBEEF);

        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), excessiveAmount);

        vm.prank(user);
        vm.expectRevert("Solde GLD insuffisant");
        goldBridge.bridgeToBSC{value: FEE}(excessiveAmount, recipient);
    }

    function testBridgeToBSCTransferFromFails() public {
    uint256 amount = 100e18;
    address recipient = address(0xBEEF);

    // Pour simuler un échec de transferFrom, n'effectuez pas d'approbation (allownance reste à 0)
    vm.prank(user);
    vm.expectRevert("Allowance exceeded");
    goldBridge.bridgeToBSC{value: FEE}(amount, recipient);
    }

    function testBridgeToBSCApproveGoldFails() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        vm.prank(user);
        bool approved = mockGoldToken.approve(address(goldBridge), amount * 10);
        assertTrue(approved, "User approval should succeed");

        // Forcer le retour false pour approve sur le GoldToken.
        mockGoldToken.setApproveReturnValue(false);

        vm.prank(user);
        vm.expectRevert("Approbation du token Gold echouee");
        goldBridge.bridgeToBSC{value: FEE}(amount, recipient);

        mockGoldToken.setApproveReturnValue(true);
    }

    function testBridgeToBSCInsufficientEth() public {
        uint256 amount = 100e18;
        address recipient = address(0xBEEF);

        vm.prank(user);
        bool approved = mockGoldToken.approve(address(goldBridge), amount * 10);
        assertTrue(approved, "Approval should succeed");

        // Construire le même message CCIP que dans la fonction pour obtenir le fee.
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
        uint256 requiredFee = mockRouter.getFee(goldBridge.BSC_CHAIN_SELECTOR(), evmMsg);

        // Envoyer moins d'ETH que requis.
        vm.prank(user);
        vm.expectRevert("Solde ETH insuffisant pour les frais");
        goldBridge.bridgeToBSC{value: requiredFee - 1}(amount, recipient);
    }

    // --- Tests pour la fonction _ccipReceive via testCcipReceive() ---
    
    function testCcipReceiveSuccess() public {
        uint256 amount = 50e18;
        // Mint des tokens Gold dans le bridge pour que le transfert soit possible.
        mockGoldToken.mint(address(goldBridge), amount);

        // Créer un message CCIP valide.
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveSuccess"),
            sourceChainSelector: goldBridge.BSC_CHAIN_SELECTOR(), // Doit être égal à BSC_CHAIN_SELECTOR.
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        uint256 initialUserGold = mockGoldToken.balanceOf(user);
        uint256 initialBridgeGold = mockGoldToken.balanceOf(address(goldBridge));

        goldBridge.testCcipReceive(message);

        // Vérifier que l'utilisateur a bien reçu les tokens.
        assertEq(
            mockGoldToken.balanceOf(user),
            initialUserGold + amount,
            "User should receive tokens from bridge"
        );
        // Vérifier que le solde du bridge diminue du montant transféré.
        assertEq(
            mockGoldToken.balanceOf(address(goldBridge)),
            initialBridgeGold - amount,
            "Bridge balance should decrease by transferred amount"
        );
    }

    function testCcipReceiveWrongChain() public {
        uint256 amount = 50e18;
        // Créer un message avec un mauvais sourceChainSelector.
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveWrongChain"),
            sourceChainSelector: 1234,  // Valeur incorrecte.
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert("Message non provenant de BSC");
        goldBridge.testCcipReceive(message);
    }

    function testCcipReceiveTransferFails() public {
        uint256 amount = 50e18;
        // Mint des tokens Gold dans le bridge pour que le transfert soit tenté.
        mockGoldToken.mint(address(goldBridge), amount);

        // Simuler un échec de transfert en forçant le mock à retourner false.
        mockGoldToken.setTransferReturnValue(false);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: keccak256("testCcipReceiveTransferFails"),
            sourceChainSelector: goldBridge.BSC_CHAIN_SELECTOR(),
            sender: abi.encode(user),
            data: abi.encode(amount),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert("Transfert de token vers le destinataire echoue");
        goldBridge.testCcipReceive(message);

        mockGoldToken.setTransferReturnValue(true);
    }
}