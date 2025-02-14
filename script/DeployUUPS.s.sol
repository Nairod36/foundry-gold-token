// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/GoldenBridge.sol";
import "../src/GoldenTokenUUPS.sol";
import "../src/Lottery.sol";
import "../src/LotteryPool.sol";
import "../test/mock/MockRouterClient.sol";
import "../test/mock/MockVRFCoordinatorV2Plus.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {

    function testA() public {} // forge coverage ignore-file

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Déploiement du LotteryPool
        LotteryPool pool = new LotteryPool();
        console.log("LotteryPool deployed to:", address(pool));

        Lottery lottery = new Lottery(payable(pool), 1);

        // Récupération des adresses des feeds Chainlink et de l'admin
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

        address payable goldenTokenAddress = payable(address(goldenTokenProxy));

        // Utilisez l'instance du proxy pour appeler mint
        GoldenTokenUUPS goldenToken = GoldenTokenUUPS(goldenTokenAddress);


        console.log("Minting tokens...");
        uint256 ethToSend = 1 ether; // Modifier selon les besoins
        goldenToken.mint{value: ethToSend}();
        console.log("Mint successful");

        // Démarrer la loterie
        console.log("Starting the lottery...");
        lottery.startLottery();
        console.log("Lottery started");

        vm.stopBroadcast();
    }
}
