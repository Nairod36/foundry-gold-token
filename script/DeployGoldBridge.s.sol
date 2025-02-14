// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/GoldenBridge.sol";

contract DeployGoldenBridge is Script {

    function testA() public {} // forge coverage ignore-file

    function run() external {
        // Récupérer la clé privée depuis l'environnement (.env)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        address recipient = vm.envAddress("RECIPIENT_ADDRESS");
        // Récupérer les adresses depuis les variables d'environnement
        address router = vm.envAddress("ROUTER_ADDRESS_SEPO");
        address goldToken = vm.envAddress("GOLDENTOKEN_ADDRESS");

        vm.startBroadcast(deployerKey);
        
        // Déployer le contrat GoldBridge
        GoldenBridge bridge = new GoldenBridge(router, goldToken);
        console.log("GoldBridge deployed at:", address(bridge));
        
        uint256 amount = 100e18; // Montant de tokens à bridger.
        uint256 feeProvided = 10e18;
        
        // Affichage pour le suivi.
        console.log("Recipient on BSC", recipient);

        // Remarque : dans un vrai environnement, l'utilisateur doit d'abord approuver le contrat GoldenBridge
        // pour dépenser ses tokens Gold. Ici, on suppose que cette étape est déjà faite ou gérée via un test préalable.
        bytes32 messageId = bridge.bridgeToBSC{value: feeProvided}(amount, recipient);

        console.log("Bridge request sent with message ID:", messageId);

        vm.stopBroadcast();
    }
}