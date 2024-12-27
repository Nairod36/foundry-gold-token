// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../contracts/GoldToken.sol";

contract GoldTokenTest is Test {
    GoldToken goldToken;

    // On pourra mocker l'aggregator
    address priceFeedXAU = address(0x123);
    address priceFeedETH = address(0x456);

    function setUp() public {
        // Déployer le contrat
        goldToken = new GoldToken(priceFeedXAU, priceFeedETH);
        // On mocke les réponses de priceFeedXAU et priceFeedETH via cheatcodes (foundry).
        // ...
    }

    function testMint() public {
        // Simule un utilisateur envoyant 1 ETH à la fonction `mint()`
        vm.deal(address(this), 1 ether);

        // On appelle la fonction mint
        (bool success,) = address(goldToken).call{value: 1 ether}(
            abi.encodeWithSignature("mint()")
        );
        assertTrue(success, "Mint should succeed");

        // Vérifier le solde en GLD
        uint256 balance = goldToken.balanceOf(address(this));
        assertGt(balance, 0, "Should have minted some GLD");
    }

    // etc...
}