// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title LotteryPool
 * @notice A smart contract that manages the prize pool for the lottery, allowing deposits and withdrawals.
 */
contract LotteryPool is Ownable {
    /// @notice Tracks deposits made by each address
    mapping(address => uint256) public deposits;
    /// @notice List of depositors who have contributed to the pool
    address[] public depositors;
    /// @notice Address of the Lottery contract authorized to withdraw funds
    address public lottery;

    event Deposited(address indexed depositor, uint256 amount);
    event Withdrawn(address indexed withdrawer, uint256 amount);
    event AwardedPrize(address indexed winner, uint256 amount);

    /**
     * @notice Initializes the contract and sets the owner.
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Returns the current balance of the pool in ETH.
     * @return The contract's ETH balance.
     */
    function balance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Sets the address of the Lottery contract authorized to withdraw funds.
     * @param _lottery Address of the Lottery contract.
     */
    function setLottery(address _lottery) external onlyOwner {
        lottery = _lottery;
    }
    
    /**
     * @notice Deposits ETH into the pool.
     * @dev Ensures that only non-zero amounts are deposited.
     */
    function deposit() external payable {
        require(msg.value > 0, "Amount must be greater than 0");
        if (deposits[msg.sender] == 0) {
            depositors.push(msg.sender);
        }
        deposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /**
     * @notice Withdraws a specified amount of ETH from the pool.
     * @dev Can only be called by the contract owner or the authorized Lottery contract.
     * @param amount The amount to withdraw in wei.
     */
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        require(address(this).balance >= amount, "Insufficient balance");
        require(msg.sender == owner() || msg.sender == lottery, "Not authorized");
        payable(msg.sender).transfer(amount);
        emit Withdrawn(msg.sender, amount);
    }

    /**
     * @notice Retrieves the list of depositors and their respective deposit amounts.
     * @return _depositors Array of depositors' addresses.
     * @return _amounts Array of deposited amounts corresponding to each depositor.
     */
    function getDepositors() external view returns (address[] memory _depositors, uint256[] memory _amounts) {
        uint256 len = depositors.length;
        _depositors = new address[](len);
        _amounts = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            _depositors[i] = depositors[i];
            _amounts[i] = deposits[depositors[i]];
        }
    }

    /**
     * @notice Accepts direct ETH transfers and registers the sender as a depositor.
     */
    receive() external payable {
        if (msg.value > 0) {
            if (deposits[msg.sender] == 0) {
                depositors.push(msg.sender);
            }
            deposits[msg.sender] += msg.value;
            emit Deposited(msg.sender, msg.value);
        }
    }
}
