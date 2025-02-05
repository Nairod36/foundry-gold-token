// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LotteryPool is Ownable {
    IERC20 public rewardToken;

    mapping(address => uint256) public deposits;
    address[] public depositors;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 amount);
    event AwardedPrize(address indexed winner, uint256 amount);

    constructor(IERC20 _rewardToken) Ownable(msg.sender) {
        require(address(_rewardToken) != address(0), "Invalid token address");
        rewardToken = _rewardToken;
    }

    /**
     * @notice Retrieves the current balance of the pool.
     * @return The current balance of the pool.
     */
    function balance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }
    
    /**
     * @notice Deposits the specified amount of tokens into the pool.
     * @param amount The amount of tokens to deposit.
     */
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        if(deposits[msg.sender] == 0) {
            depositors.push(msg.sender);
        }
        deposits[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /**
     * @notice Withdraws the specified amount of tokens from the pool.
     * @param amount The amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        require(deposits[msg.sender] >= amount, "Insufficient balance");
        deposits[msg.sender] -= amount;
        require(rewardToken.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Retrieves the list of depositors along with their deposit amounts.
     * @return _depositors An array of depositor addresses.
     * @return _amounts An array of deposit amounts corresponding to each depositor.
     */
     function getDepositors() external onlyOwner view returns (address[] memory _depositors, uint256[] memory _amounts) {
        uint256 len = depositors.length;
        _depositors = new address[](len);
        _amounts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            _depositors[i] = depositors[i];
            _amounts[i] = deposits[depositors[i]];
        }
        return (_depositors, _amounts);
    }

}