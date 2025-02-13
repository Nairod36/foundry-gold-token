// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/GoldenBridge.sol";

contract DeployGoldenBridge is Script {

            function testA() public {} // forge coverage ignore-file

    function run() external {
        // Récupérer la clé privée depuis l'environnement (.env)
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Récupérer les adresses depuis les variables d'environnement
        address router = vm.envAddress("ROUTER_ADDRESS");
        address goldToken = vm.envAddress("GOLDTOKEN_ADDRESS");

        vm.startBroadcast(deployerKey);
        
        // Déployer le contrat GoldBridge
        GoldenBridge bridge = new GoldenBridge(router, goldToken);
        console.log("GoldBridge deployed at:", address(bridge));
        
        vm.stopBroadcast();
    }
}