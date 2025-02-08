// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/GoldToken.sol";
import "../src/Lottery.sol";
import { MockAggregator } from "./mock/MockAggregator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Fichier de tests pour GoldToken, couvrant l’ensemble des branches.
 */
contract GoldTokenTest is Test {
    GoldToken public goldToken;
    Lottery public lottery;    
    MockAggregator public mockGoldAggregator;
    MockAggregator public mockEthAggregator;

    address public user = address(0x123);
    address public adminFeeCollector = address(0x456);

    // Dummy events pour expectEmit
    event PriceFeedsUpdated(address indexed goldFeed, address indexed ethFeed);
    event Minted(address indexed minter, uint256 ethAmount, uint256 netTokenAmount);
    event Burned(address indexed burner, uint256 tokenAmount, uint256 refundEth);

    function setUp() public {
        // Déployer des agrégateurs mock avec des valeurs réalistes :
        // Gold feed renvoie 2000 (ex. 2000 USD) et ETH feed 1500 (ex. 1500 USD)
        mockGoldAggregator = new MockAggregator(2000, block.timestamp, 1, 18);
        mockEthAggregator = new MockAggregator(1500, block.timestamp, 1, 18);
        // Déploiement d'un contrat Lottery dummy (son implémentation n'est pas utilisée ici)
        lottery = new Lottery(IERC20(address(0x1)));

        // Déploiement de GoldToken avec des adresses valides
        goldToken = new GoldToken(
            AggregatorV3Interface(address(mockGoldAggregator)),
            AggregatorV3Interface(address(mockEthAggregator)),
            ILottery(address(lottery)),
            adminFeeCollector
        );
        // En tant qu'owner, on définit les feeds de prix
        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(mockGoldAggregator, mockEthAggregator);
    }

    /* ============================
               GETTERS
       ============================ */

    function testGetGoldPrice() view public {
        uint256 price = goldToken.getGoldPrice();
        assertEq(price, 2000, "Gold price should be 2000");
    }

    function testGetEthPrice() view public {
        uint256 price = goldToken.getEthPrice();
        assertEq(price, 1500, "ETH price should be 1500");
    }

    function testPreviewMint() view public {
        uint256 ethAmount = 1e18; // 1 ETH
        // Calcul attendu : usdAmount = (1e18 * 1500)/1e18 = 1500
        // tokenAmount = (1500 * 1e18)/2000 = 0.75e18
        uint256 expected = (1500 * 1e18) / 2000;
        uint256 preview = goldToken.previewMint(ethAmount);
        assertEq(preview, expected, "Preview mint amount mismatch");
    }

    /// @notice Teste que getGoldPrice() revoit une erreur si le feed renvoie une valeur négative.
    function testGetGoldPriceRevertNegative() public {
        MockAggregator negativeGoldAggregator = new MockAggregator(-100, block.timestamp, 1, 18);
        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(negativeGoldAggregator, mockEthAggregator);
        vm.expectRevert("Invalid gold price");
        goldToken.getGoldPrice();
    }

    /// @notice Teste que getEthPrice() revoit une erreur si le feed renvoie une valeur négative.
    function testGetEthPriceRevertNegative() public {
        MockAggregator negativeEthAggregator = new MockAggregator(-100, block.timestamp, 1, 18);
        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(mockGoldAggregator, negativeEthAggregator);
        vm.expectRevert("Invalid ETH price");
        goldToken.getEthPrice();
    }

    /* ============================
        MINT
    ============================ */

    function testMint() public {
        uint256 ethSent = 1e18; // 1 ETH
        // Calcul du montant brut de tokens : previewMint(1e18)
        uint256 grossTokenAmount = goldToken.previewMint(ethSent);
        // Frais de 5%
        uint256 feeTokens = (grossTokenAmount * 5) / 100;
        uint256 netTokenAmount = grossTokenAmount - feeTokens;
        // Répartition des frais : 50% chacun
        uint256 feeForAdmin = feeTokens / 2;
        uint256 feeForLottery = feeTokens - feeForAdmin;

        // Approvisionner l'utilisateur en ETH
        vm.deal(user, ethSent);

        // Utiliser startPrank pour éviter de recouvrir un prank
        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Minted(user, ethSent, netTokenAmount);
        goldToken.mint{value: ethSent}();
        vm.stopPrank();

        // Vérification des soldes en tokens
        assertEq(goldToken.balanceOf(user), netTokenAmount, "User token balance incorrect");
        assertEq(goldToken.balanceOf(adminFeeCollector), feeForAdmin, "Admin fee balance incorrect");
        assertEq(goldToken.balanceOf(address(lottery)), feeForLottery, "Lottery fee balance incorrect");
    }

    function testMintRevertNoEth() public {
        vm.startPrank(user);
        vm.expectRevert("Must send ETH to mint tokens");
        goldToken.mint{value: 0}();
        vm.stopPrank();
    }

    function testMintRevertInsufficientEthForMinting() public {
        // Simuler un prix de l'or très élevé afin que previewMint retourne 0 tokens.
        MockAggregator hugeGoldAggregator = new MockAggregator(1e30, block.timestamp, 1, 18);
        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(hugeGoldAggregator, mockEthAggregator);

        vm.deal(user, 1e18);
        vm.startPrank(user);
        vm.expectRevert("Insufficient ETH for minting");
        goldToken.mint{value: 1e18}();
        vm.stopPrank();
    }

    /* ============================
        CONSTRUCTOR REVERT TESTS
    ============================ */
    function testConstructorRevertInvalidGoldFeed() public {
        vm.expectRevert("Invalid gold feed address");
        new GoldToken(
            AggregatorV3Interface(address(0)),
            AggregatorV3Interface(address(mockEthAggregator)),
            ILottery(address(lottery)),
            adminFeeCollector
        );
    }

    function testConstructorRevertInvalidEthFeed() public {
        vm.expectRevert("Invalid ETH feed address");
        new GoldToken(
            AggregatorV3Interface(address(mockGoldAggregator)),
            AggregatorV3Interface(address(0)),
            ILottery(address(lottery)),
            adminFeeCollector
        );
    }

    function testConstructorRevertInvalidLottery() public {
        vm.expectRevert("Invalid lottery address");
        new GoldToken(
            AggregatorV3Interface(address(mockGoldAggregator)),
            AggregatorV3Interface(address(mockEthAggregator)),
            ILottery(address(0)),
            adminFeeCollector
        );
    }

    function testConstructorRevertInvalidAdminFeeCollector() public {
        vm.expectRevert("Invalid admin fee collector address");
        new GoldToken(
            AggregatorV3Interface(address(mockGoldAggregator)),
            AggregatorV3Interface(address(mockEthAggregator)),
            ILottery(address(lottery)),
            address(0)
        );
    }

    /* ============================
        SET PRICE FEEDS
    ============================ */

    function testSetPriceFeeds() public {
        MockAggregator newGoldAggregator = new MockAggregator(2500, block.timestamp, 2, 18);
        MockAggregator newEthAggregator = new MockAggregator(1600, block.timestamp, 2, 18);

        vm.expectEmit(true, true, false, false);
        emit PriceFeedsUpdated(address(newGoldAggregator), address(newEthAggregator));

        vm.prank(goldToken.owner());
        goldToken.setPriceFeeds(newGoldAggregator, newEthAggregator);

        uint256 goldPrice = goldToken.getGoldPrice();
        uint256 ethPrice = goldToken.getEthPrice();
        assertEq(goldPrice, 2500, "New gold price mismatch");
        assertEq(ethPrice, 1600, "New ETH price mismatch");
    }

    function testSetPriceFeedsNonOwner() public {
        MockAggregator newGoldAggregator = new MockAggregator(2500, block.timestamp, 2, 18);
        MockAggregator newEthAggregator = new MockAggregator(1600, block.timestamp, 2, 18);

        vm.prank(user);
        vm.expectRevert();
        goldToken.setPriceFeeds(newGoldAggregator, newEthAggregator);
    }

    function testSetPriceFeedsRevertInvalidAddress() public {
        vm.prank(goldToken.owner());
        vm.expectRevert("Invalid gold feed address");
        goldToken.setPriceFeeds(AggregatorV3Interface(address(0)), mockEthAggregator);

        vm.prank(goldToken.owner());
        vm.expectRevert("Invalid ETH feed address");
        goldToken.setPriceFeeds(mockGoldAggregator, AggregatorV3Interface(address(0)));
    }

    /* ============================
        BURN
    ============================ */

    function testBurn() public {
        // 1) L'utilisateur mint des tokens
        uint256 ethSent = 1e18;
        vm.deal(user, ethSent);
        vm.startPrank(user);
        goldToken.mint{value: ethSent}();
        vm.stopPrank();

        uint256 userTokenBalance = goldToken.balanceOf(user);
        // L'utilisateur brûle la moitié de ses tokens
        uint256 burnAmount = userTokenBalance / 2;

        // Soldes initiaux
        uint256 adminBalanceBefore = goldToken.balanceOf(adminFeeCollector);
        uint256 lotteryBalanceBefore = goldToken.balanceOf(address(lottery));

        // Calcul des frais sur le burn
        uint256 feeTokens = (burnAmount * 5) / 100;
        uint256 netTokens = burnAmount - feeTokens;
        uint256 ethPrice = goldToken.getEthPrice();
        uint256 goldPrice = goldToken.getGoldPrice();
        // Calcul du remboursement en ETH :
        // refundEth = (netTokens * goldPrice * ETH_DECIMALS) / (TOKEN_DECIMALS * MINT_RATIO * ethPrice)
        uint256 refundEth = (netTokens * goldPrice * 1e18) / (1e18 * 1 * ethPrice);
        uint256 userEthBefore = user.balance;

        vm.startPrank(user);
        vm.expectEmit(true, true, false, true);
        emit Burned(user, burnAmount, refundEth);
        goldToken.burn(burnAmount);
        vm.stopPrank();

        uint256 userTokenAfter = goldToken.balanceOf(user);
        assertEq(userTokenAfter, userTokenBalance - burnAmount, "User token balance not reduced correctly");

        uint256 feeForAdmin = feeTokens / 2;
        uint256 feeForLottery = feeTokens - feeForAdmin;
        assertEq(
            goldToken.balanceOf(adminFeeCollector),
            adminBalanceBefore + feeForAdmin,
            "Admin fee not received correctly"
        );
        assertEq(
            goldToken.balanceOf(address(lottery)),
            lotteryBalanceBefore + feeForLottery,
            "Lottery fee not received correctly"
        );

        uint256 userEthAfter = user.balance;
        uint256 refundReceived = userEthAfter - userEthBefore;
        // Tolérance pour variations de gas
        assertApproxEqAbs(refundReceived, refundEth, 1e14);
    }

    function testBurnRevertZeroToken() public {
        vm.startPrank(user);
        vm.expectRevert("Token amount must be greater than 0");
        goldToken.burn(0);
        vm.stopPrank();
    }

    function testBurnRevertInsufficientTokenBalance() public {
        vm.startPrank(user);
        vm.expectRevert("Insufficient token balance");
        goldToken.burn(1e18);
        vm.stopPrank();
    }

    function testBurnRevertInsufficientContractBalance() public {
        uint256 ethSent = 1e18;
        vm.deal(user, ethSent);
        vm.startPrank(user);
        goldToken.mint{value: ethSent}();
        vm.stopPrank();

        uint256 userTokenBalance = goldToken.balanceOf(user);
        // Forcer le solde ETH du contrat à 0
        vm.deal(address(goldToken), 0);

        vm.startPrank(user);
        vm.expectRevert("Contract balance insufficient for refund");
        goldToken.burn(userTokenBalance);
        vm.stopPrank();
    }

    /// @notice Teste le cas où le transfert d'ETH échoue dans burn() grâce à un utilisateur qui rejette les ETH.
    function testBurnRevertEthTransferFailed() public {
        RevertingReceiver receiver = new RevertingReceiver();
        vm.deal(address(receiver), 1e18);
        vm.prank(address(receiver));
        goldToken.mint{value: 1e18}();
        uint256 tokenBalance = goldToken.balanceOf(address(receiver));
        vm.prank(address(receiver));
        vm.expectRevert("ETH transfer failed");
        goldToken.burn(tokenBalance);
    }

    /* ============================
        RECEIVE
    ============================ */
    function testReceive() public {
        uint256 amount = 1e18;
        address sender = address(0x789);
        vm.deal(sender, amount);
        // Transfert direct d'ETH vers le contrat
        payable(address(goldToken)).transfer(amount);
        assertEq(address(goldToken).balance, amount, "Contract did not receive ETH");
    }
}

/**
 * @notice Ce contrat rejette systématiquement la réception d'ETH.
 * Il est utilisé pour tester la branche "ETH transfer failed" dans burn().
 */
contract RevertingReceiver {
    fallback() external payable {
        revert("I reject ETH");
    }
    receive() external payable {
        revert("I reject ETH");
    }
}