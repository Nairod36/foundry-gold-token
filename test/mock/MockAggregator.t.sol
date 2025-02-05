// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../../src/GoldToken.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract MockAggregator is AggregatorV3Interface {
    int256 private _latestAnswer;
    uint256 private _latestTimestamp;
    uint256 private _latestRound;
    uint256 private _decimals;

    constructor(int256 latestAnswer, uint256 latestTimestamp, uint256 latestRound, uint256 decimals_) {
        _latestAnswer = latestAnswer;
        _latestTimestamp = latestTimestamp;
        _latestRound = latestRound;
        _decimals = decimals_;
    }

    // Implementation of latestRoundData()
    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (uint80(_latestRound), _latestAnswer, _latestTimestamp, _latestTimestamp, uint80(_latestRound));
    }

    // Implementation of getRoundData()
    function getRoundData(uint80 /* _roundId */)
        external
        view
        override
        returns (
            uint80 roundID,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (uint80(_latestRound), _latestAnswer, _latestTimestamp, _latestTimestamp, uint80(_latestRound));
    }

    // Implementation of decimals()
    function decimals() external view override returns (uint8) {
        return uint8(_decimals);
    }

    // Implementation of description()
    function description() external pure override returns (string memory) {
        return "Mock Aggregator";
    }

    // Implementation of version()
    function version() external pure override returns (uint256) {
        return 1;
    }
}