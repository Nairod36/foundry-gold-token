// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LotteryPool.sol";
import './mock/MockERC20.sol';

// Declare the custom error so we can check for it in expectRevert calls.
error OwnableUnauthorizedAccount(address);

contract LotteryPoolTest is Test {
    // On utilisera le MockERC20 pour les tests standards.
    MockERC20 public token;
    LotteryPool public lotteryPool;

    // Adresses de test.
    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        // Le contrat de test (this) est le propriétaire.
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);

        // Déployer le MockERC20 (token standard) pour les tests.
        token = new MockERC20("Test Token", "TST", 18);

        // Minter des tokens pour user1 et user2.
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);

        // Déployer le contrat LotteryPool en utilisant le token.
        lotteryPool = new LotteryPool(IERC20(address(token)));
    }

    /* ============================
              CONSTRUCTOR
       ============================ */

    function testConstructorRevertsWithZeroToken() public {
        // Vérifie que le constructeur reverte si l'adresse du token est zéro.
        vm.expectRevert("Invalid token address");
        new LotteryPool(IERC20(address(0)));
    }

    /* ============================
              GETTERS & BALANCE
       ============================ */

    function testBalanceInitiallyZero() public {
        uint256 bal = lotteryPool.balance();
        assertEq(bal, 0, "Initial pool balance should be zero");
    }

    function testPoolBalanceAfterDeposit() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        uint256 poolBalance = token.balanceOf(address(lotteryPool));
        assertEq(poolBalance, depositAmount, "Pool balance should equal deposit amount");

        // Vérification via la fonction balance()
        uint256 balanceFromFunction = lotteryPool.balance();
        assertEq(balanceFromFunction, depositAmount, "balance() should return deposit amount");
    }

    /* ============================
              DEPOSIT
       ============================ */

    function testDepositRevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        lotteryPool.deposit(0);
    }

    function testDepositSingleUser() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        uint256 deposited = lotteryPool.deposits(user1);
        assertEq(deposited, depositAmount, "Deposited amount mismatch");

        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 1, "There should be 1 depositor");
        assertEq(depositors[0], user1, "Depositor address mismatch");
        assertEq(amounts[0], depositAmount, "Deposited amount in list mismatch");
    }

    function testDepositAggregationForSameUser() public {
        uint256 firstDeposit = 50 ether;
        uint256 secondDeposit = 75 ether;
        uint256 totalExpected = firstDeposit + secondDeposit;

        vm.prank(user1);
        token.approve(address(lotteryPool), totalExpected);
        vm.prank(user1);
        lotteryPool.deposit(firstDeposit);
        vm.prank(user1);
        lotteryPool.deposit(secondDeposit);

        uint256 totalDeposited = lotteryPool.deposits(user1);
        assertEq(totalDeposited, totalExpected, "Aggregated deposit mismatch");

        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 1, "Depositors list should have one entry");
        assertEq(depositors[0], user1, "Depositor address mismatch");
        assertEq(amounts[0], totalExpected, "Deposited amount mismatch in list");
    }

    function testDepositMultipleUsers() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;

        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount1);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount1);

        vm.prank(user2);
        token.approve(address(lotteryPool), depositAmount2);
        vm.prank(user2);
        lotteryPool.deposit(depositAmount2);

        assertEq(lotteryPool.deposits(user1), depositAmount1, "User1 deposit mismatch");
        assertEq(lotteryPool.deposits(user2), depositAmount2, "User2 deposit mismatch");

        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 2, "There should be 2 depositors");
        // L'ordre est celui dans lequel les adresses déposent pour la première fois.
        assertEq(depositors[0], user1, "First depositor should be user1");
        assertEq(amounts[0], depositAmount1, "User1 amount mismatch");
        assertEq(depositors[1], user2, "Second depositor should be user2");
        assertEq(amounts[1], depositAmount2, "User2 amount mismatch");
    }

    // Test pour simuler un échec du transferFrom dans deposit() à l'aide d'un token défaillant.
    function testDepositRevertsIfTransferFromFails() public {
        // Déployer un ERC20 qui échoue.
        MockERC20 failingToken = new MockERC20("Failing Token", "FAIL", 18);
        // Minter des tokens pour user1.
        failingToken.mint(user1, 1000 ether);
        // Déployer un nouveau LotteryPool avec failingToken.
        LotteryPool failingPool = new LotteryPool(IERC20(address(failingToken)));

        vm.prank(user1);
        failingToken.approve(address(failingPool), 100 ether);
        // Forcer l'échec du transferFrom.
        failingToken.setFail(true);
        vm.prank(user1);
        vm.expectRevert("Transfer failed");
        failingPool.deposit(100 ether);
    }

    /* ============================
              WITHDRAW
       ============================ */

    function testWithdrawRevertsForNonOwner() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        // Tentative de retrait par user1 (non-owner).
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));
        lotteryPool.withdraw(depositAmount);
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        lotteryPool.withdraw(0);
    }

    function testWithdrawRevertsOnInsufficientBalance() public {
        // Aucun dépôt pour l'owner → balance = 0.
        vm.prank(owner);
        vm.expectRevert("Insufficient balance");
        lotteryPool.withdraw(1 ether);
    }

    function testWithdrawSuccessful() public {
        uint256 depositAmount = 150 ether;
        // Pour ce test, l'owner dépose des tokens.
        token.mint(owner, depositAmount);
        token.approve(address(lotteryPool), depositAmount);
        lotteryPool.deposit(depositAmount);

        uint256 ownerBalanceBefore = token.balanceOf(owner);
        uint256 withdrawAmount = 50 ether;

        vm.prank(owner);
        lotteryPool.withdraw(withdrawAmount);

        uint256 remainingDeposit = lotteryPool.deposits(owner);
        assertEq(remainingDeposit, depositAmount - withdrawAmount, "Remaining deposit mismatch");

        uint256 ownerBalanceAfter = token.balanceOf(owner);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + withdrawAmount, "Owner balance after withdraw mismatch");
    }

    // Test pour simuler un échec du transfer dans withdraw() à l'aide d'un token défaillant.
    function testWithdrawRevertsIfTransferFails() public {
        // Déployer un token qui peut échouer.
        MockERC20 failingToken = new MockERC20("Failing Token", "FAIL", 18);
        failingToken.mint(owner, 1000 ether);

        // Déployer un LotteryPool avec failingToken.
        LotteryPool failingPool = new LotteryPool(IERC20(address(failingToken)));
        failingToken.approve(address(failingPool), 100 ether);
        failingPool.deposit(100 ether);

        // Forcer l'échec de transfer.
        failingToken.setFail(true);
        vm.prank(owner);
        vm.expectRevert("Transfer failed");
        failingPool.withdraw(50 ether);
    }

    /* ============================
          GET DEPOSITORS (ACCESS)
       ============================ */

    function testGetDepositorsRevertsForNonOwner() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        // La fonction getDepositors est réservée au propriétaire.
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1));
        lotteryPool.getDepositors();
    }

    // Test pour vérifier que getDepositors retourne des tableaux vides si aucun dépôt n'a été effectué.
    function testGetDepositorsEmpty() public {
        // En tant que propriétaire, on appelle getDepositors sans qu'aucune adresse n'ait déposé.
        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 0, "Depositors list should be empty");
        assertEq(amounts.length, 0, "Amounts list should be empty");
    }
}