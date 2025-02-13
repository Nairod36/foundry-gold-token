// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/GoldenBridge.sol";
import "../src/GoldenTokenUUPS.sol";
import "../src/Lottery.sol";
import "../src/LotteryPool.sol";
// import "../test/mock/MockAggregator.sol";
import "../test/mock/MockRouterClient.sol";
import "../test/mock/MockVRFCoordinatorV2Plus.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {

            function testA() public {} // forge coverage ignore-file

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Déploiement du LotteryPool
        LotteryPool lotteryPool = new LotteryPool();

        Lottery lottery = new Lottery(payable(lotteryPool), 1);

        address goldAggregatorAddress = vm.envAddress("GOLD_AGGREGATOR_ADDRESS");
        address ethAggregatorAddress  = vm.envAddress("ETH_AGGREGATOR_ADDRESS");

        address adminFeeCollector = vm.envAddress("ADMIN_FEE_COLLECTOR");
        
         // Déploiement de l'implémentation de GoldToken
        GoldenTokenUUPS goldenTokenImpl = new GoldenTokenUUPS();

        bytes memory initData = abi.encodeWithSelector(
            GoldenTokenUUPS.initialize.selector,
            AggregatorV3Interface(goldAggregatorAddress),
            AggregatorV3Interface(ethAggregatorAddress),
            ILottery(address(lottery)),
            adminFeeCollector
        );

        ERC1967Proxy goldenTokenProxy = new ERC1967Proxy(
            address(goldenTokenImpl),
            initData
        );

        // On peut interagir avec GoldenTokenUUPS via l'adresse du proxy which got an address payable
        console.log("GoldenToken deployed to :", address(goldenTokenProxy));
        address payable goldenTokenAddress = payable(address(goldenTokenProxy));

        GoldenTokenUUPS goldenToken = GoldenTokenUUPS(goldenTokenAddress);
    }
}