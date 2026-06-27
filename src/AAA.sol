// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAggregator {
    function latestRound() external view returns (uint256);
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80);
}
