// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console2.sol"; // Import de console2 pour pouvoir utiliser console2.log
import "../src/GoldenToken.sol";
import "../src/GoldenBridge.sol";
import "../src/Lottery.sol";

contract UseCase is Script {

        function testA() public {} // forge coverage ignore-file

    function run() external {
        vm.startBroadcast();

        // Récupération des adresses des contrats déployés via les variables d'environnement
        address goldTokenAddress = vm.envAddress("GOLDTOKEN_ADDRESS");
        address goldBridgeAddress = vm.envAddress("GOLDBRIDGE_ADDRESS");
        address lotteryAddress = vm.envAddress("LOTTERY_ADDRESS");

        // Conversion en payable pour les contrats possédant une fonction receive payable
        GoldenToken goldToken = GoldenToken(payable(goldTokenAddress));
        GoldenBridge goldBridge = GoldenBridge(goldBridgeAddress);
        Lottery lottery = Lottery(payable(lotteryAddress));

        address user = msg.sender;

        // --- 1. Mint de tokens Gold ---
        console2.log("Minting GoldToken...");
        goldToken.mint{value: 1 ether}();
        console2.log("User GoldToken balance:", goldToken.balanceOf(user));

        // --- 2. Participation à la loterie ---
        // Démarrer la loterie (la fonction startLottery est réservée au propriétaire)
        console2.log("Starting Lottery...");
        lottery.startLottery();

        // Pour participer, on envoie 10 ether directement au contrat Lottery (trigger du receive)
        console2.log("Entering Lottery...");
        (bool success, ) = address(lottery).call{value: 10 ether}("");
        require(success, "Lottery participation failed");
        console2.log("Lottery participation confirmed!");

        // --- 3. Bridging vers BSC ---
        console2.log("Bridging tokens...");
        goldToken.approve(address(goldBridge), 50e18);
        bytes32 messageId = goldBridge.bridgeToBSC(50e18, user);
        // Affichage du messageId converti en uint256
        console2.log("Bridge transaction ID (as uint256):", uint256(messageId));
        // Vous pouvez aussi utiliser : console2.logBytes32(messageId);

        vm.stopBroadcast();
    }
}