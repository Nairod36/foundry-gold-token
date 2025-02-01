// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GoldToken is ERC20, Ownable {
    AggregatorV3Interface public priceFeed; 

    /**
     * @dev Constructeur. On transmet `msg.sender` à Ownable pour faire 
     * du déployeur le propriétaire par défaut.
     */
    constructor()
        ERC20("Gold Token", "GLD")
        Ownable(msg.sender) 
    {
        // On récupère l'adresse de l'aggregator pour le prix de l'or
        priceFeed = AggregatorV3Interface(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6);
    }

    function getPrice(AggregatorV3Interface _priceFeed) public view returns (uint256) {
        (, int256 answer, , , ) = _priceFeed.latestRoundData();
        return uint256(answer);
    }

    function getDecimals(AggregatorV3Interface _priceFeed) public view returns (uint8) {
        return _priceFeed.decimals();
    }
        
      /**
     * Returns the latest answer.
     */
    function getChainlinkDataFeedLatestAnswer() public view returns (int) {
        // prettier-ignore
        (
            /* uint80 roundID */,
            int answer,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        return answer;
    }
}