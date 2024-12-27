// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import "forge-std/Script.sol";
// import "../contracts/GoldToken.sol";
// import "../contracts/Lottery.sol";
// import "../contracts/GoldBridge.sol";

// contract Deploy is Script {
//     function run() external {
//         vm.startBroadcast();

//         // Adresses Chainlink Aggregators (mainnet)
//         address XAU_USD = 0x214f6bb8b9C55F7E3e59F977704b88Ae68DaD2A8; 
//         address ETH_USD = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612; 
        
//         // Déploiement GoldToken
//         GoldToken goldToken = new GoldToken(XAU_USD, ETH_USD);

//         // Déploiement Lottery
//         // Données VRF : on met des placeholders
//         address vrfCoordinator = address(0xVRF);
//         bytes32 keyHash = 0x00;
//         uint64 subId = 0;
//         uint16 confirmations = 3;
//         uint32 gasLimit = 200000;
//         Lottery lottery = new Lottery(
//             vrfCoordinator,
//             keyHash,
//             subId,
//             confirmations,
//             gasLimit,
//             address(goldToken)
//         );

//         // Lier GoldToken <-> Lottery
//         goldToken.setLotteryContract(address(lottery));

//         // Déploiement Bridge
//         address ccipRouter = address(0xCCIP);
//         GoldBridge goldBridge = new GoldBridge(ccipRouter, address(goldToken));

//         vm.stopBroadcast();
//     }
// }