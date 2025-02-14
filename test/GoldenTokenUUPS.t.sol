// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Import the token and mocks
import "../src/GoldenTokenUUPS.sol";
import "./mock/MockAggregator.sol";
import "./mock/MockRevertingReceiver.sol";
import "../src/Lottery.sol";
import "./mock/MockGoldenTokenUUPS.sol";

/// @notice Minimal interface to expose upgradeTo
interface IUUPSUpgradeable {
    function upgradeTo(address newImplementation) external;
}

/// @title Tests pour GoldenTokenUUPS (version upgradeable via UUPS)
contract GoldenTokenUUPSTest is Test {
    // Dummy test to avoid warnings
    function testA() public {}

    GoldenTokenUUPS public token;
    Lottery public lottery;    
    MockAggregator public mockGoldAggregator;
    MockAggregator public mockEthAggregator;
    LotteryPool public pool;
    
    address public user = address(0x123);
    address public adminFeeCollector = address(0x456);

    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);

    function setUp() public {
        // The aggregators will return 2000 and 1500 (8 decimals expected)
        mockGoldAggregator = new MockAggregator(2000, block.timestamp, 1, 18);
        mockEthAggregator = new MockAggregator(1500, block.timestamp, 1, 18);
        pool = new LotteryPool();

        lottery = new Lottery(payable(address(pool)), 1);

        // Deploy the implementation and the proxy
        GoldenTokenUUPS implementation = new GoldenTokenUUPS();
        bytes memory data = abi.encodeWithSelector(
            GoldenTokenUUPS.initialize.selector,
            mockGoldAggregator,
            mockEthAggregator,
            lottery,
            adminFeeCollector
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        // Conversion to payable is necessary
        token = GoldenTokenUUPS(payable(address(proxy)));
    }

    // --- Fonctions de lecture et preview ---
    function testGetGoldPrice() view public {
        uint256 price = token.getGoldPrice();
        assertEq(price, 2000, "The gold price should be 2000");
    }

    function testGetEthPrice() view public {
        uint256 price = token.getEthPrice();
        assertEq(price, 1500, "The ETH price should be 1500");
    }

    function testPreviewMint() view public {
        uint256 ethAmount = 1e18;
        // Calcul attendu :
        // usdAmount = (1e18 * 1500) / 1e18 = 1500
        // grossTokenAmount = (1500 * 1e18) / 2000 = 0.75e18
        uint256 expected = (1500 * 1e18) / 2000;
        uint256 preview = token.previewMint(ethAmount);
        assertEq(preview, expected, "Mismatch on preview mint amount");
    }

    // --- Tests pour setPriceFeeds ---
    function testSetPriceFeeds() public {
        MockAggregator newGoldAggregator = new MockAggregator(2500, block.timestamp, 2, 18);
        MockAggregator newEthAggregator = new MockAggregator(1600, block.timestamp, 2, 18);

        vm.expectEmit(true, true, false, false);
        emit PriceFeedsUpdated(address(newGoldAggregator), address(newEthAggregator));

        vm.prank(token.owner());
        token.setPriceFeeds(newGoldAggregator, newEthAggregator);

        uint256 goldPrice = token.getGoldPrice();
        uint256 ethPrice = token.getEthPrice();
        assertEq(goldPrice, 2500, "New gold price is incorrect");
        assertEq(ethPrice, 1600, "New ETH price is incorrect");
    }

    function testSetPriceFeedsNonOwner() public {
        MockAggregator newGoldAggregator = new MockAggregator(2500, block.timestamp, 2, 18);
        MockAggregator newEthAggregator = new MockAggregator(1600, block.timestamp, 2, 18);

        vm.prank(user);
        vm.expectRevert();
        token.setPriceFeeds(newGoldAggregator, newEthAggregator);
    }

    function testSetPriceFeedsRevertInvalidAddress() public {
        vm.prank(token.owner());
        vm.expectRevert("Invalid gold feed address");
        token.setPriceFeeds(AggregatorV3Interface(address(0)), mockEthAggregator);

        vm.prank(token.owner());
        vm.expectRevert("Invalid ETH feed address");
        token.setPriceFeeds(mockGoldAggregator, AggregatorV3Interface(address(0)));
    }

    // --- Tests pour mint ---
    function testMint() public {
        uint256 ethSent = 1e18;
        uint256 grossTokenAmount = token.previewMint(ethSent);
        uint256 feeTokens = (grossTokenAmount * 5) / 100;
        uint256 netTokenAmount = grossTokenAmount - feeTokens;
        uint256 feeForAdmin = feeTokens / 2;
        uint256 feeForLottery = feeTokens - feeForAdmin;

        vm.deal(user, ethSent);

        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Minted(user, ethSent, netTokenAmount);
        token.mint{value: ethSent}();
        vm.stopPrank();

        assertEq(token.balanceOf(user), netTokenAmount, "User token balance incorrect");
        assertEq(token.balanceOf(adminFeeCollector), feeForAdmin, "Admin fee balance incorrect");
        assertEq(token.balanceOf(address(lottery)), feeForLottery, "Lottery fee balance incorrect");
    }

    function testMintRevertNoEth() public {
        vm.startPrank(user);
        vm.expectRevert("Must send ETH to mint tokens");
        token.mint{value: 0}();
        vm.stopPrank();
    }

    function testMintRevertInsufficientEthForMinting() public {
        // Fixer le prix de l'or très haut pour que previewMint renvoie zéro tokens
        MockAggregator hugeGoldAggregator = new MockAggregator(1e30, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(hugeGoldAggregator, mockEthAggregator);

        vm.deal(user, 1e18);
        vm.startPrank(user);
        vm.expectRevert("Insufficient ETH for minting");
        token.mint{value: 1e18}();
        vm.stopPrank();
    }

    // --- Tests pour burn ---
    function testBurnSuccess() public {
        // L'utilisateur minte des tokens en envoyant 1 ETH
        uint256 ethSent = 1e18;
        vm.deal(user, ethSent);
        vm.startPrank(user);
        token.mint{value: ethSent}();
        uint256 userTokenBalance = token.balanceOf(user);
        
        // Enregistrer les soldes avant le burn
        uint256 lotteryBalanceBefore = token.balanceOf(address(lottery));
        uint256 adminBalanceBefore = token.balanceOf(adminFeeCollector);
        
        // Calcul des frais sur burn et montant net brûlé
        uint256 burnFee = (userTokenBalance * 5) / 100;
        uint256 netTokensBurn = userTokenBalance - burnFee;
        uint256 refundEth = (netTokensBurn * 2000) / 1500;
        uint256 initialContractBalance = address(token).balance;
        
        vm.expectEmit(true, true, false, true);
        emit Burned(user, userTokenBalance, refundEth);
        token.burn(userTokenBalance);
        vm.stopPrank();
        
        // Vérifier que le solde de l'utilisateur est à 0
        assertEq(token.balanceOf(user), 0, "User token balance should be zero after burn");
        // Vérifier l'incrément des frais pour la loterie et le collector
        uint256 lotteryIncrement = token.balanceOf(address(lottery)) - lotteryBalanceBefore;
        assertEq(lotteryIncrement, burnFee / 2, "Lottery fee tokens incorrect after burn");
        uint256 adminIncrement = token.balanceOf(adminFeeCollector) - adminBalanceBefore;
        assertEq(adminIncrement, burnFee / 2, "Admin fee tokens incorrect after burn");
        // Vérifier le solde ETH du contrat
        assertEq(address(token).balance, initialContractBalance - refundEth, "Contract ETH balance did not decrease correctly after burn");
    }

    function testBurnRevertZeroToken() public {
        vm.prank(user);
        vm.expectRevert("Token amount must be greater than 0");
        token.burn(0);
    }

    function testBurnRevertInsufficientTokenBalance() public {
        vm.prank(user);
        vm.expectRevert("Insufficient token balance");
        token.burn(1);
    }

    function testBurnRevertInsufficientContractBalance() public {
        uint256 ethSent = 1e18;
        vm.deal(user, ethSent);
        vm.startPrank(user);
        token.mint{value: ethSent}();
        uint256 userTokenBalance = token.balanceOf(user);
        vm.stopPrank();
        // Forcer le solde ETH du contrat à 0
        vm.deal(address(token), 0);
        vm.prank(user);
        vm.expectRevert("Contract balance insufficient for refund");
        token.burn(userTokenBalance);
    }

    function testBurnRevertTransferFailure() public {
        uint256 ethSent = 1e18;
        vm.deal(user, ethSent);
        vm.startPrank(user);
        token.mint{value: ethSent}();
        vm.stopPrank();

        // Transférer des tokens à un contrat qui rejette la réception d'ETH (fallback/receive revert)
        MockRevertingReceiver revertReceiver = new MockRevertingReceiver();
        uint256 transferAmount = token.balanceOf(user) / 2;
        vm.startPrank(user);
        token.transfer(address(revertReceiver), transferAmount);
        vm.stopPrank();

        vm.expectRevert();
        revertReceiver.burn(address(token), transferAmount);
    }

    // --- Test de la fonction receive() ---
    function testReceiveFunction() public {
        uint256 amount = 1e17;
        (bool success, ) = address(token).call{value: amount}("");
        assertTrue(success, "Direct ETH transfer to token failed");
        assertEq(address(token).balance, amount, "Contract ETH balance incorrect after direct transfer");
    }

    // --- Tests pour getGoldPrice et getEthPrice en cas de réponse invalide ---
    function testGetGoldPriceRevert() public {
        // Agrégateur renvoyant 0
        MockAggregator zeroGoldAggregator = new MockAggregator(0, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(zeroGoldAggregator, mockEthAggregator);
        vm.expectRevert("Invalid gold price");
        token.getGoldPrice();
    }

    function testGetEthPriceRevert() public {
        // Agrégateur renvoyant 0
        MockAggregator zeroEthAggregator = new MockAggregator(0, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(mockGoldAggregator, zeroEthAggregator);
        vm.expectRevert("Invalid ETH price");
        token.getEthPrice();
    }

    function testGetGoldPriceRevertNegative() public {
        // Agrégateur renvoyant une valeur négative
        MockAggregator negativeGoldAggregator = new MockAggregator(-100, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(negativeGoldAggregator, mockEthAggregator);
        vm.expectRevert("Invalid gold price");
        token.getGoldPrice();
    }

    function testGetEthPriceRevertNegative() public {
        // Agrégateur renvoyant une valeur négative
        MockAggregator negativeEthAggregator = new MockAggregator(-100, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(mockGoldAggregator, negativeEthAggregator);
        vm.expectRevert("Invalid ETH price");
        token.getEthPrice();
    }

    // --- Tests for upgradeability ---
    function testUpgradeOwner() public {
        GoldenTokenUUPS newImplementation = new GoldenTokenUUPS();
        vm.prank(token.owner());
        token.upgradeToAndCall(address(newImplementation), "");
    }
        
    function testUpgradeNonOwner() public {
        GoldenTokenUUPS newImplementation = new GoldenTokenUUPS();
        // Pas d'appel à initialize sur newImplementation !
        vm.prank(user);
        vm.expectRevert();
        IUUPSUpgradeable(address(token)).upgradeTo(address(newImplementation));
    }
}
