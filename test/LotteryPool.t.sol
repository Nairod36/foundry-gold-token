pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/LotteryPool.sol";
import "./mock/MockLottery.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract LotteryPoolTest is Test {
    LotteryPool public pool;
    address public owner;
    address public user1 = address(0x1);
    address public user2 = address(0x2);

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 amount);

    function setUp() public {
        pool = new LotteryPool();
        // Transfer ownership to an EOA to avoid test contract's fallback rejecting ETH
        pool.transferOwnership(address(0x3));
        owner = address(0x3);
    }

    function testDeposit() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        
        vm.expectEmit(false, false, false, true);
        emit Deposited(user1, depositAmount);
        
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        
        uint256 deposited = pool.deposits(user1);
        assertEq(deposited, depositAmount, "Deposit amount mismatch");

        (address[] memory depositors, uint256[] memory amounts) = pool.getDepositors();
        bool found = false;
        for (uint256 i = 0; i < depositors.length; i++) {
            if (depositors[i] == user1 && amounts[i] == depositAmount) {
                found = true;
                break;
            }
        }
        assertTrue(found, "Depositor not found in list");
    }

    function testDepositRevertZero() public {
        vm.prank(user1);
        vm.expectRevert("Amount must be greater than 0");
        pool.deposit{value: 0}();
    }

    function testReceiveFunction() public {
        uint256 depositAmount = 0.5 ether;
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool success, ) = address(pool).call{value: depositAmount}("");
        assertTrue(success, "Receive function failed");
        
        uint256 deposited = pool.deposits(user2);
        assertEq(deposited, depositAmount, "Receive deposit amount mismatch");
    }

    function testWithdrawByOwner() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        
        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit Withdrawn(owner, depositAmount);
        pool.withdraw(depositAmount);
        
        assertEq(address(pool).balance, 0, "Pool balance should be zero after withdrawal");
    }

    function testWithdrawByLottery() public {
        // Deploy a mock Lottery that can receive ETH
        MockLottery mockLottery = new MockLottery();
        
        vm.prank(owner);
        pool.setLottery(address(mockLottery));
        
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        
        vm.prank(address(mockLottery));
        vm.expectEmit(false, false, false, true);
        emit Withdrawn(address(mockLottery), depositAmount);
        pool.withdraw(depositAmount);
        
        assertEq(address(pool).balance, 0, "Pool balance should be zero after withdrawal by lottery");
    }

    function testWithdrawNotAuthorized() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        
        vm.prank(user2);
        vm.expectRevert("Not authorized");
        pool.withdraw(depositAmount);
    }

    function testWithdrawInsufficientBalance() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        
        vm.prank(owner);
        vm.expectRevert("Insufficient balance");
        pool.withdraw(depositAmount + 1 ether);
    }

    function testWithdrawZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("Amount must be greater than 0");
        pool.withdraw(0);
    }

    function testGetDepositors() public {
        uint256 deposit1 = 1 ether;
        vm.deal(user1, deposit1);
        vm.prank(user1);
        pool.deposit{value: deposit1}();
        
        uint256 deposit2 = 0.5 ether;
        vm.deal(user2, deposit2);
        vm.prank(user2);
        pool.deposit{value: deposit2}();
        
        uint256 deposit3 = 0.5 ether;
        vm.deal(user1, deposit3);
        vm.prank(user1);
        pool.deposit{value: deposit3}();
        
        (address[] memory depositors, uint256[] memory amounts) = pool.getDepositors();
        uint256 user1Total;
        uint256 user2Total;
        for (uint256 i = 0; i < depositors.length; i++) {
            if (depositors[i] == user1) {
                user1Total = amounts[i];
            } else if (depositors[i] == user2) {
                user2Total = amounts[i];
            }
        }
        assertEq(user1Total, deposit1 + deposit3, "user1 total deposit mismatch");
        assertEq(user2Total, deposit2, "user2 total deposit mismatch");
    }

    function testGetDepositorsEmpty() public view {
        (address[] memory depositors, uint256[] memory amounts) = pool.getDepositors();
        assertEq(depositors.length, 0, "Expected no depositors");
        assertEq(amounts.length, 0, "Expected no amounts");
    }

    function testReceiveZero() public {
        uint256 initialBalance = address(pool).balance;
        vm.prank(user2);
        (bool success, ) = address(pool).call{value: 0}("");
        assertTrue(success, "Receive with 0 ETH should succeed");
        assertEq(address(pool).balance, initialBalance, "Balance should remain unchanged");
        uint256 deposited = pool.deposits(user2);
        assertEq(deposited, 0, "Deposits for user2 should remain 0");
    }

    function testFallbackFunction() public {
        uint256 depositAmount = 0.5 ether;
        vm.deal(user2, 1 ether);
        vm.prank(user2);
        (bool success, ) = address(pool).call{value: depositAmount}(hex"1234");
        assertTrue(success, "Fallback function failed");
        
        uint256 deposited = pool.deposits(user2);
        assertEq(deposited, depositAmount, "Fallback deposit amount mismatch");
    }

    function testFallbackZeroValue() public {
        vm.prank(user2);
        (bool success, ) = address(pool).call{value: 0}(hex"1234");
        assertTrue(success, "Fallback with 0 ETH should succeed");
        uint256 deposited = pool.deposits(user2);
        assertEq(deposited, 0, "Deposits for user2 should remain 0");
    }

    function testSetLottery() public {
        address lotteryAddress = address(0xABC);
        vm.prank(owner);
        pool.setLottery(lotteryAddress);
        assertEq(pool.lottery(), lotteryAddress, "Lottery address not set correctly");
    }

    function testSetLotteryNotOwner() public {
        address lotteryAddress = address(0xABC);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user1));
        pool.setLottery(lotteryAddress);
    }

    function testBalance() public {
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        pool.deposit{value: depositAmount}();
        uint256 bal = pool.balance();
        assertEq(bal, depositAmount, "Balance function returned incorrect amount");
    }
}