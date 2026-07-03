// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

interface IAggregator {
    function latestRound() external view returns (uint256);
    function getRoundData(uint80 roundId)
        external
        view
        returns (uint80, int256 answer, uint256 startedAt, uint256 updatedAt, uint80);
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80);
}

/**
 * AAA. A rating agency with nobody inside.
 *
 * In 2008 the AAA stamp was something people sold. This contract hands out the
 * same letters and cannot be talked to, paid, or pressured, because there is
 * nobody in the building. A grade is computed from the feed's own published
 * round history, on chain, at the moment you ask. Ask again and it is computed
 * again. There is no committee, no analyst, no owner, and nothing to update.
 *
 * What is graded: how faithfully a tokenized equity's price feed shows up for
 * work. The agency walks the feed's stored rounds and measures its worst
 * silence during US market hours (weekends, holidays and the overnight are
 * not held against it; the exchange calendar lives in this contract), how
 * often its price walked A to B and straight back to A, whether it is dark
 * right now, and how much history it has at all. Thin files cap the grade,
 * the way a borrower with no history cannot be prime.
 */
contract AAA {
    uint256 public constant LOOKBACK = 300; // rounds walked per grading

    address[] public feeds; // aggregators, where the rounds are stored
    string[] public names;

    struct Metrics {
        uint256 rounds; // rounds actually on file
        uint256 worstSilence; // longest quiet stretch during market hours, seconds
        uint256 silentNow; // market-hours seconds since the last print
        uint256 roundTrips; // price went A -> B -> exactly A
}
}
