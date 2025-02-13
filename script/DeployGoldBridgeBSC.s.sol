// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/GoldenBridgeBSC.sol";

contract DeployGoldBridgeBSC is Script {

            function testA() public {} // forge coverage ignore-file

    function run() external {
        // Récupérer la clé privée depuis l'environnement
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");

        // Récupérer les adresses pour le réseau BSC depuis les variables d'environnement
        address router = vm.envAddress("ROUTER_BSC_ADDRESS_BSC");
        address goldToken = vm.envAddress("GOLDTOKEN_BSC_ADDRESS");

        vm.startBroadcast(deployerKey);
        
        // Déployer le contrat GoldBridgeBSC
        GoldBridgeBSC bridgeBSC = new GoldBridgeBSC(router, goldToken);
        console.log("GoldBridgeBSC deployed at:", address(bridgeBSC));
        
        vm.stopBroadcast();
    }
}