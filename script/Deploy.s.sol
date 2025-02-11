// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/GoldBridge.sol";
import "../src/GoldToken.sol";
import "../src/Lottery.sol";
import "../src/LotteryPool.sol";
import "../test/mock/MockAggregator.sol";
import "../test/mock/MockRouterClient.sol";
import "../test/mock/MockVRFCoordinatorV2Plus.sol";

contract Deploy is Script {
    function run() external {
        // Déploiement des mocks pour les agrégateurs et le routeur CCIP
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Déploiement du LotteryPool
        LotteryPool lotteryPool = new LotteryPool();
        console.log("LotteryPool deploy on :", address(lotteryPool));

        Lottery lottery = new Lottery(payable(lotteryPool), 1);
        console.log("Lottery deploy :", address(lottery));

        address goldAggregatorAddress = vm.envAddress("GOLD_AGGREGATOR_ADDRESS");
        address ethAggregatorAddress  = vm.envAddress("ETH_AGGREGATOR_ADDRESS");

         // Adresse du collecteur des frais administratifs (configurable)
        address adminFeeCollector = vm.envAddress("ADMIN_FEE_COLLECTOR");

        GoldToken goldToken = new GoldToken(
            AggregatorV3Interface(goldAggregatorAddress),
            AggregatorV3Interface(ethAggregatorAddress),
            lottery,
            adminFeeCollector
        );

        console.log("GoldToken deployed to :", address(goldToken));
    }

}