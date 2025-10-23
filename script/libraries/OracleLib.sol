// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title OracleLib
 * @author Abdul Badamasi
 * @notice THis library is used to check the Chainlink Oracle for stale date.
 * If a price is stale, the function will revert and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze is price becomes stale.
 *
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol... too bad
 */

 library OracleLib {
    error OracleLib__StalePrice();
    uint256 private constant STALE_PRICE_THRESHOLD = 3 hours; // 3 * 60 * 60 seconds
    function staleCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = 
            priceFeed.latestRoundData();

        uint256 secondsSinceLastUpdate = block.timestamp - updatedAt;
        if (secondsSinceLastUpdate > STALE_PRICE_THRESHOLD) {
            revert OracleLib__StalePrice();
        }

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
 }