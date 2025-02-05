// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/LotteryPool.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Declare the custom error so we can check for it in expectRevert calls.
error OwnableUnauthorizedAccount(address);

// A minimal mock ERC20 token for testing purposes.
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {}

    /// @notice Mint tokens to a specified address.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract LotteryPoolTest is Test {
    MockERC20 public token;
    LotteryPool public lotteryPool;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        // Set up test addresses.
        owner = address(this); // The test contract is the owner.
        user1 = address(0x1);
        user2 = address(0x2);

        // Deploy the mock ERC20 token.
        token = new MockERC20();

        // Mint tokens for testing to user1 and user2.
        token.mint(user1, 1000 ether);
        token.mint(user2, 1000 ether);

        // Deploy the LotteryPool contract.
        // Note: We call the constructor of LotteryPool with owner = msg.sender.
        lotteryPool = new LotteryPool(IERC20(address(token)));
    }

    /* ============================
        Test balance() function
    ============================ */
    function testBalanceInitiallyZero() public view {
        uint256 bal = lotteryPool.balance();
        assertEq(bal, 0, "Initial pool balance should be zero");
    }

    /* ============================
        Test deposit() functionality
    ============================ */
    function testDepositRevertsOnZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        lotteryPool.deposit(0);
    }

    function testDepositSingleUser() public {
        uint256 depositAmount = 100 ether;
        // Have user1 approve the LotteryPool contract.
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);

        // Deposit from user1.
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        // Verify the mapping is updated.
        uint256 deposited = lotteryPool.deposits(user1);
        assertEq(deposited, depositAmount, "Deposited amount mismatch");

        // As owner, call getDepositors to retrieve the list.
        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 1, "There should be 1 depositor");
        assertEq(depositors[0], user1, "Depositor address mismatch");
        assertEq(amounts[0], depositAmount, "Deposited amount in list mismatch");
    }

    function testDepositAggregationForSameUser() public {
        uint256 firstDeposit = 50 ether;
        uint256 secondDeposit = 75 ether;
        uint256 totalExpected = firstDeposit + secondDeposit;

        // Approve and deposit first time.
        vm.prank(user1);
        token.approve(address(lotteryPool), totalExpected);
        vm.prank(user1);
        lotteryPool.deposit(firstDeposit);

        // Deposit a second time.
        vm.prank(user1);
        lotteryPool.deposit(secondDeposit);

        // Check that the deposit mapping aggregates the deposits.
        uint256 totalDeposited = lotteryPool.deposits(user1);
        assertEq(totalDeposited, totalExpected, "Aggregated deposit mismatch");

        // Ensure depositors list has only one entry.
        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 1, "Depositors list should have one entry");
        assertEq(depositors[0], user1, "Depositor address mismatch");
        assertEq(amounts[0], totalExpected, "Deposited amount mismatch in list");
    }

    function testDepositMultipleUsers() public {
        uint256 depositAmount1 = 100 ether;
        uint256 depositAmount2 = 200 ether;

        // user1 deposits.
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount1);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount1);

        // user2 deposits.
        vm.prank(user2);
        token.approve(address(lotteryPool), depositAmount2);
        vm.prank(user2);
        lotteryPool.deposit(depositAmount2);

        // Check deposits mapping.
        assertEq(lotteryPool.deposits(user1), depositAmount1, "User1 deposit mismatch");
        assertEq(lotteryPool.deposits(user2), depositAmount2, "User2 deposit mismatch");

        // Check depositors list.
        (address[] memory depositors, uint256[] memory amounts) = lotteryPool.getDepositors();
        assertEq(depositors.length, 2, "There should be 2 depositors");
        // Order is preserved as deposits are pushed when first depositing.
        assertEq(depositors[0], user1, "First depositor should be user1");
        assertEq(amounts[0], depositAmount1, "User1 amount mismatch");
        assertEq(depositors[1], user2, "Second depositor should be user2");
        assertEq(amounts[1], depositAmount2, "User2 amount mismatch");
    }

    /* ============================
        Test withdraw() functionality
    ============================ */
    function testWithdrawRevertsForNonOwner() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        // Attempt to call withdraw from user1 (not the owner).
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        lotteryPool.withdraw(depositAmount);
    }

    function testWithdrawRevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        lotteryPool.withdraw(0);
    }

    function testWithdrawRevertsOnInsufficientBalance() public {
        // The owner (this contract) hasn't deposited anything, so deposits[owner] == 0.
        vm.prank(owner);
        vm.expectRevert("Insufficient balance");
        lotteryPool.withdraw(1 ether);
    }

    function testWithdrawSuccessful() public {
        uint256 depositAmount = 150 ether;
        // For testing, mint tokens to owner and deposit them.
        token.mint(owner, depositAmount);
        token.approve(address(lotteryPool), depositAmount);
        lotteryPool.deposit(depositAmount);

        // Record owner's token balance before withdraw.
        uint256 ownerBalanceBefore = token.balanceOf(owner);

        uint256 withdrawAmount = 50 ether;
        vm.prank(owner);
        lotteryPool.withdraw(withdrawAmount);

        // Check that deposits for owner is reduced.
        uint256 remainingDeposit = lotteryPool.deposits(owner);
        assertEq(remainingDeposit, depositAmount - withdrawAmount, "Remaining deposit mismatch");

        // Check that owner's token balance increased by the withdrawn amount.
        uint256 ownerBalanceAfter = token.balanceOf(owner);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + withdrawAmount, "Owner balance after withdraw mismatch");
    }

    /* ============================
        Test getDepositors() access control
    ============================ */
    function testGetDepositorsRevertsForNonOwner() public {
        uint256 depositAmount = 100 ether;
        vm.prank(user1);
        token.approve(address(lotteryPool), depositAmount);
        vm.prank(user1);
        lotteryPool.deposit(depositAmount);

        // getDepositors is restricted to owner only.
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, user1)
        );
        lotteryPool.getDepositors();
    }
}
