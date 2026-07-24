// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {AAA, IAggregator} from "../src/AAA.sol";

contract MockAggregator is IAggregator {
    int256[] answers;
    uint256[] times;

    function push(int256 answer, uint256 at) public {
        answers.push(answer);
        times.push(at);
    }

    function latestRound() external view returns (uint256) {
        return answers.length;
    }

    function getRoundData(uint80 id) external view returns (uint80, int256, uint256, uint256, uint80) {
        return (id, answers[id - 1], times[id - 1], times[id - 1], id);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint256 n = answers.length;
        return (uint80(n), answers[n - 1], times[n - 1], times[n - 1], uint80(n));
    }
}

