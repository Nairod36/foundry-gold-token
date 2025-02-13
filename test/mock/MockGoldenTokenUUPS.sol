// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/GoldenTokenUUPS.sol";

contract GoldenTokenUUPS_V2 is GoldenTokenUUPS {

    function testA() public {}
    
    function version() public pure returns (string memory) {
        return "V2";
    }
}