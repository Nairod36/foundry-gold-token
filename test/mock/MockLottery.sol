// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

contract MockLottery {
    // Fallback qui accepte de l'ETH sans rien faire
    receive() external payable {}
    fallback() external payable {}
}
