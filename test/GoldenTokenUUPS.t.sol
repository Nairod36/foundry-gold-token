// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/GoldenTokenUUPS.sol";
import "./mock/MockAggregator.sol";
import "./mock/MockRevertingReceiver.sol";
import "../src/Lottery.sol";
import "./mock/MockGoldenTokenUUPS.sol";

/// @title Tests pour GoldenTokenUUPS (version upgradeable via UUPS)
contract GoldenTokenUUPSTest is Test {
       
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
        // Les agrégateurs renverront respectivement 2000 et 1500 (8 décimales attendues)
        mockGoldAggregator = new MockAggregator(2000, block.timestamp, 1, 18);
        mockEthAggregator = new MockAggregator(1500, block.timestamp, 1, 18);
        pool = new LotteryPool();

        lottery = new Lottery(payable(pool), 1);

        // Déploiement de l'implémentation et du proxy
        GoldenTokenUUPS implementation = new GoldenTokenUUPS();
        bytes memory data = abi.encodeWithSelector(
            GoldenTokenUUPS.initialize.selector,
            mockGoldAggregator,
            mockEthAggregator,
            lottery,
            adminFeeCollector
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        // Conversion vers payable nécessaire
        token = GoldenTokenUUPS(payable(address(proxy)));
    }

    // --- Fonctions de lecture et preview ---

    function testGetGoldPrice() public {
        uint256 price = token.getGoldPrice();
        assertEq(price, 2000, "The gold price should be 2000");
    }

    function testGetEthPrice() public {
        uint256 price = token.getEthPrice();
        assertEq(price, 1500, "The ETH price should be 1500");
    }

    function testPreviewMint() public {
        uint256 ethAmount = 1e18;
        // Calcul attendu :
        // usdAmount = (1e18 * 1500) / 1e18 = 1500
        // grossTokenAmount = (1500 * 1e18) / 2000 = 0.75e18
        uint256 expected = (1500 * 1e18) / 2000;
        uint256 preview = token.previewMint(ethAmount);
        assertEq(preview, expected, "Mismatch on preview mint amount");
    }

    // --- Tests de setPriceFeeds ---

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
        vm.expectRevert(); // Ne pas spécifier le message car il peut varier
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
        // En fixant le prix de l'or très haut, previewMint renvoie zéro tokens
        MockAggregator hugeGoldAggregator = new MockAggregator(1e30, block.timestamp, 1, 18);
        vm.prank(token.owner());
        token.setPriceFeeds(hugeGoldAggregator, mockEthAggregator);

        vm.deal(user, 1e18);
        vm.startPrank(user);
        vm.expectRevert("Insufficient ETH for minting");
        token.mint{value: 1e18}();
        vm.stopPrank();
    }

}