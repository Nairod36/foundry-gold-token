// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GoldBridge.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @dev Pour comparer l’erreur levée par Ownable dans notre environnement (versions récentes d’OpenZeppelin)
error OwnableUnauthorizedAccount(address);

/// -------------------------------------------------------------------------
///                            MOCKS POUR LES TESTS
/// -------------------------------------------------------------------------

/// @notice Mock de l'interface CCIP qui enregistre les paramètres de l'appel.
contract MockCCIP is IChainlinkCCIP {
    uint256 public lastDestinationChain;
    bytes public lastMessage;
    address public lastReceiver;
    IERC20 public lastToken;
    uint256 public lastAmount;

    function ccipSend(
        uint256 destinationChainSelector,
        bytes calldata message,
        IERC20[] calldata tokens,
        uint256[] calldata amounts,
        address receiver
    ) external payable override {
        lastDestinationChain = destinationChainSelector;
        lastMessage = message;
        lastReceiver = receiver;
        require(tokens.length > 0, "Tokens array empty");
        lastToken = tokens[0];
        require(amounts.length > 0, "Amounts array empty");
        lastAmount = amounts[0];
    }
}

/// @notice Implémentation minimale d’un ERC20 pour les tests.
contract MockERC20 is IERC20 {
    string public name = "Mock Gold Token";
    string public symbol = "MGT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) public {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Allowance exceeded");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;
        return true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Implémentation d’un ERC20 dont les transferts échouent systématiquement.
contract FailingERC20Impl is IERC20 {
    string public constant name = "Failing Token";
    string public constant symbol = "FAIL";
    uint8 public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    /// @notice Permet de forcer le solde d’un compte.
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
        totalSupply = amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address, uint256) external override returns (bool) {
        return false;
    }

    function approve(address, uint256) external override returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external override returns (bool) {
        return false;
    }

    function allowance(address, address) external view override returns (uint256) {
        return 0;
    }
}

/// -------------------------------------------------------------------------
///                           TESTS DU GOLDBRIDGE
/// -------------------------------------------------------------------------

contract GoldBridgeTest is Test {
    GoldBridge public goldBridge;
    MockCCIP public mockCCIP;
    MockERC20 public mockGoldToken;

    address public owner = address(this); // L'owner sera celui qui déploie le test.
    address public user = address(0x123);
    address public nonOwner = address(0x456);

    // Dans le setUp, on déploie le MockCCIP, le MockERC20 et le GoldBridge,
    // on mint des tokens pour l'utilisateur et on autorise la chaîne d'ID 100.
    function setUp() public {
        mockCCIP = new MockCCIP();
        mockGoldToken = new MockERC20();
        // Mint 1000 tokens (avec 18 décimales) pour l'utilisateur.
        mockGoldToken.mint(user, 1000 * 1e18);

        goldBridge = new GoldBridge(address(mockCCIP), address(mockGoldToken));
        // Autoriser une chaîne (par exemple, chainID 100).
        goldBridge.authorizeChain(100);
    }

    /* ============================================
                   CONSTRUCTEUR
       ============================================ */

    function testConstructorInvalidCCIP() public {
        vm.expectRevert("Invalid CCIP address");
        new GoldBridge(address(0), address(mockGoldToken));
    }

    function testConstructorInvalidGoldToken() public {
        vm.expectRevert("Invalid gold token address");
        new GoldBridge(address(mockCCIP), address(0));
    }

    /* ============================================
                   AUTHORIZE CHAIN
       ============================================ */

    function testAuthorizeChain() public {
        uint256 chainId = 200;
        // Appel depuis l'owner (address(this)).
        goldBridge.authorizeChain(chainId);
        bool authorized = goldBridge.authorizedChains(chainId);
        assertTrue(authorized, "Chain should be authorized");
    }

    function testAuthorizeChainNonOwner() public {
        uint256 chainId = 300;
        vm.prank(nonOwner);
        // On s'attend à ce que l'appel échoue avec l'erreur OwnableUnauthorizedAccount(nonOwner)
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, nonOwner));
        goldBridge.authorizeChain(chainId);
    }

    /* ============================================
                    BRIDGE TO CHAIN
       ============================================ */

    // Cas de succès de bridgeToChain.
    function testBridgeToChainSuccess() public {
        uint256 amount = 100 * 1e18;
        uint256 chainId = 100; // chaîne autorisée

        // L'utilisateur doit approuver le pont pour déduire ses tokens.
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);

        // On vérifie l'émission de l'événement BridgeSent.
        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit GoldBridge.BridgeSent(chainId, user, amount);
        goldBridge.bridgeToChain(chainId, amount, user);

        // Vérification que le pont (GoldBridge) a reçu les tokens.
        uint256 bridgeBalance = mockGoldToken.balanceOf(address(goldBridge));
        assertEq(bridgeBalance, amount, "Bridge should have received tokens");

        // Vérification que le mock CCIP a bien reçu les paramètres.
        assertEq(mockCCIP.lastDestinationChain(), chainId, "Destination chain mismatch");
        bytes memory expectedMessage = abi.encode("bridge GLD");
        assertEq(keccak256(mockCCIP.lastMessage()), keccak256(expectedMessage), "Message mismatch");
        assertEq(address(mockCCIP.lastToken()), address(mockGoldToken), "Token mismatch in CCIP call");
        assertEq(mockCCIP.lastAmount(), amount, "Amount mismatch in CCIP call");
        assertEq(mockCCIP.lastReceiver(), user, "Receiver mismatch in CCIP call");
    }

    // Revert si la chaîne n'est pas autorisée.
    function testBridgeToChainRevertChainNotAuthorized() public {
        uint256 chainId = 999; // chaîne non autorisée
        uint256 amount = 100 * 1e18;
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);
        vm.prank(user);
        vm.expectRevert("Chain not authorized");
        goldBridge.bridgeToChain(chainId, amount, user);
    }

    // Revert si l'utilisateur n'a pas assez de tokens.
    function testBridgeToChainRevertNotEnoughGLD() public {
        uint256 amount = 2000 * 1e18; // L'utilisateur n'a que 1000 tokens mintés
        uint256 chainId = 100;
        vm.prank(user);
        mockGoldToken.approve(address(goldBridge), amount);
        vm.prank(user);
        vm.expectRevert("Not enough GLD");
        goldBridge.bridgeToChain(chainId, amount, user);
    }

    // Revert si transferFrom échoue.
    // Pour ce test, nous déployons un pont utilisant un token qui échoue.
    function testBridgeToChainRevertTransferFailed() public {
        FailingERC20Impl failingToken = new FailingERC20Impl();
        // Simuler un solde pour l'utilisateur (via setBalance) afin qu'il "dispose" des tokens,
        // mais le transfert échouera toujours.
        vm.prank(user);
        failingToken.setBalance(user, 1000 * 1e18);
        GoldBridge bridge = new GoldBridge(address(mockCCIP), address(failingToken));
        bridge.authorizeChain(100);
        vm.prank(user);
        failingToken.approve(address(bridge), 100 * 1e18);
        vm.prank(user);
        vm.expectRevert("Transfer failed");
        bridge.bridgeToChain(100, 100 * 1e18, user);
    }

    /* ============================================
                     CCIP RECEIVE
       ============================================ */

    // Cas de succès de ccipReceive.
    function testCcipReceiveSuccess() public {
        uint256 chainId = 100;
        uint256 amount = 50 * 1e18;
        // Pour que le pont puisse transférer des tokens via ccipReceive,
        // on "mint" (crédite) des tokens dans le GoldBridge.
        mockGoldToken.mint(address(goldBridge), amount);

        // Préparation des tableaux pour l'appel.
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = mockGoldToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        // Appel de ccipReceive depuis le contrat CCIP (msg.sender == address(mockCCIP)).
        vm.prank(address(mockCCIP));
        vm.expectEmit(true, true, true, true);
        emit GoldBridge.BridgeReceived(chainId, user, amount);
        goldBridge.ccipReceive(chainId, tokens, amounts, user);

        // Vérification que le destinataire (user) a été crédité.
        uint256 userBalance = mockGoldToken.balanceOf(user);
        // L'utilisateur avait initialement 1000 tokens, il doit les retrouver plus le montant transféré.
        assertEq(userBalance, 1000 * 1e18 + amount, "User did not receive tokens from ccipReceive");
    }

    // Revert si l'appelant n'est pas le CCIP.
    function testCcipReceiveRevertOnlyCCIP() public {
        uint256 chainId = 100;
        uint256 amount = 10 * 1e18;
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = mockGoldToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.prank(user); // appelant non autorisé
        vm.expectRevert("Only CCIP can call");
        goldBridge.ccipReceive(chainId, tokens, amounts, user);
    }

    // Revert si la chaîne source n'est pas autorisée.
    function testCcipReceiveRevertChainNotAuthorized() public {
        uint256 chainId = 999; // non autorisée
        uint256 amount = 10 * 1e18;
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = mockGoldToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.prank(address(mockCCIP));
        vm.expectRevert("Chain not authorized");
        goldBridge.ccipReceive(chainId, tokens, amounts, user);
    }

    // Revert si le tableau de tokens n'a pas exactement 1 élément.
    function testCcipReceiveRevertInvalidTokensLength() public {
        uint256 chainId = 100;
        uint256 amount = 10 * 1e18;
        IERC20[] memory tokens = new IERC20[](0);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.prank(address(mockCCIP));
        vm.expectRevert("Invalid tokens array length");
        goldBridge.ccipReceive(chainId, tokens, amounts, user);
    }

    // Revert si le tableau des montants n'a pas exactement 1 élément.
    function testCcipReceiveRevertInvalidAmountsLength() public {
        uint256 chainId = 100;
        uint256 amount = 10 * 1e18;
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = mockGoldToken;
        uint256[] memory amounts = new uint256[](0);
        vm.prank(address(mockCCIP));
        vm.expectRevert("Invalid amounts array length");
        goldBridge.ccipReceive(chainId, tokens, amounts, user);
    }

    // Revert si le token fourni n'est pas le goldToken attendu.
    function testCcipReceiveRevertInvalidToken() public {
        uint256 chainId = 100;
        uint256 amount = 10 * 1e18;
        // Déployer un autre token mock.
        ConcreteMockERC20Impl otherToken = new ConcreteMockERC20Impl();
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = IERC20(address(otherToken));
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        vm.prank(address(mockCCIP));
        vm.expectRevert("Invalid token");
        goldBridge.ccipReceive(chainId, tokens, amounts, user);
    }

    // Revert si le transfert (goldToken.transfer) échoue dans ccipReceive.
    function testCcipReceiveRevertTransferFailed() public {
        // Pour ce test, déployons un GoldBridge avec un token qui échoue (FailingERC20Impl).
        FailingERC20Impl failingToken = new FailingERC20Impl();
        GoldBridge bridge = new GoldBridge(address(mockCCIP), address(failingToken));
        bridge.authorizeChain(100);
        // On simule un solde dans le pont.
        failingToken.setBalance(address(bridge), 100 * 1e18);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = failingToken;
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 100 * 1e18;
        vm.prank(address(mockCCIP));
        vm.expectRevert("Transfer failed");
        bridge.ccipReceive(100, tokens, amounts, user);
    }
}

/// -------------------------------------------------------------------------
///                 Concrete Mock ERC20 Impl
/// -------------------------------------------------------------------------

contract ConcreteMockERC20Impl is IERC20 {
    string public constant name = "Mock Token";
    string public constant symbol = "MOCK";
    uint8 public constant decimals = 18;
    uint256 public override totalSupply;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowances;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
        totalSupply += amount;
    }

    /// @notice Permet de forcer le solde d’un compte (utile pour simuler des transferts échoués).
    function setBalance(address account, uint256 amount) external {
        balances[account] = amount;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(balances[from] >= amount, "Insufficient balance");
        require(allowances[from][msg.sender] >= amount, "Insufficient allowance");
        balances[from] -= amount;
        allowances[from][msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return allowances[owner][spender];
    }
}