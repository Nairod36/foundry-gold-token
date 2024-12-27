// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.28;

// import "forge-std/Script.sol";
// import "../contracts/GoldToken.sol";
// import "../contracts/Lottery.sol";
// import "../contracts/GoldBridge.sol";

// contract UseCase is Script {
//     function run() external {
//         // On récupère les adresses depuis un .env ou depuis un script de déploiement
//         address goldTokenAddr = 0x1234...;
//         address lotteryAddr = 0x5678...;
//         address goldBridgeAddr = 0x9ABC...;

//         vm.startBroadcast();

//         GoldToken goldToken = GoldToken(goldTokenAddr);
//         Lottery lottery = Lottery(lotteryAddr);
//         GoldBridge bridge = GoldBridge(goldBridgeAddr);

//         // 1) Mint
//         goldToken.mint{value: 1 ether}();
//         // 2) Participer à la loterie
//         lottery.enter();
//         // 3) Envoyer les fees accumulés à la loterie
//         goldToken.transferFeesToLottery();
//         // 4) Lancer la loterie (VRF)
//         lottery.startLottery(); 
//         // On suppose qu'une fois VRF callback effectué, un gagnant reçoit le pot
//         // 5) Bridger des tokens
//         goldToken.approve(address(bridge), 1000);
//         bridge.bridgeToChain(56, 1000, msg.sender); // 56 = BSC
//         // etc...

//         vm.stopBroadcast();
//     }
// }