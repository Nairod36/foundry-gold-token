// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public override totalSupply;
    bool public fail;

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;

    // Variables internes pour contrôler le comportement des fonctions
    bool internal _transferReturnValue = true;
    bool internal _approveReturnValue = true;
    bool internal _transferFromReturnValue = true;

    // Line to exclude from coverage report
    function test() public {}

    // Getters (pour consultation via tests, si besoin)
    function transferReturnValue() public view returns (bool) {
        return _transferReturnValue;
    }

    function approveReturnValue() public view returns (bool) {
        return _approveReturnValue;
    }

    function transferFromReturnValue() public view returns (bool) {
        return _transferFromReturnValue;
    }

    // Setters pour simuler des échecs dans les fonctions
    function setTransferReturnValue(bool _value) external {
        _transferReturnValue = _value;
    }

    function setApproveReturnValue(bool _value) external {
        _approveReturnValue = _value;
    }

    function setTransferFromReturnValue(bool _value) external {
        _transferFromReturnValue = _value;
    }

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        require(!fail, "Transfer failed");
        if (!_transferReturnValue) return false;
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        if (!_approveReturnValue) return false;
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        require(!fail, "Transfer failed");
        if (!_transferFromReturnValue) return false;
        require(balanceOf[sender] >= amount, "Insufficient balance");
        if (msg.sender != sender) {
            require(allowance[sender][msg.sender] >= amount, "Allowance exceeded");
            allowance[sender][msg.sender] -= amount;
        }
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function setFail(bool _fail) external {
        fail = _fail;
    }
}