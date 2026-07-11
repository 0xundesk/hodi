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
        int256 last; // latest answer
    }

    constructor(address[] memory feeds_, string[] memory names_) {
        require(feeds_.length == names_.length, "lengths");
        feeds = feeds_;
        names = names_;
    }

    // ---------------------------------------------------------------- grading

    /// The letter for any feed, computed fresh from its own rounds.
    function grade(address feed) public view returns (string memory letter, Metrics memory m) {
        m = inspect(feed, LOOKBACK);
        letter = letterOf(m);
    }

    /// The whole board, one call.
    function reportCard()
        external
        view
        returns (string[] memory tickers, string[] memory letters, Metrics[] memory metrics)
    {
        uint256 n = feeds.length;
        tickers = new string[](n);
        letters = new string[](n);
        metrics = new Metrics[](n);
        for (uint256 i = 0; i < n; i++) {
            tickers[i] = names[i];
            (letters[i], metrics[i]) = grade(feeds[i]);
        }
    }

    function count() external view returns (uint256) {
        return feeds.length;
    }

    /// Walk the feed's stored rounds and measure them. Pure observation.
    function inspect(address feed, uint256 lookback) public view returns (Metrics memory m) {
        IAggregator agg = IAggregator(feed);
        uint256 latest = agg.latestRound();
        uint256 stop = latest > lookback ? latest - lookback + 1 : 1;

        uint256 newerAt;
        int256 newerAnswer;
        int256 newestAnswer2; // the answer after newerAnswer, walking backwards

        for (uint256 id = latest; id >= stop; id--) {
            (, int256 answer,, uint256 updatedAt,) = agg.getRoundData(uint80(id));
            if (answer == 0 || updatedAt == 0) {
                if (id == 1) break;
                continue;
            }
            m.rounds++;

            if (newerAt != 0) {
                uint256 quiet = openSecondsBetween(updatedAt, newerAt);
                if (quiet > m.worstSilence) m.worstSilence = quiet;
                if (newestAnswer2 != 0 && newestAnswer2 == answer && newerAnswer != answer) {
                    m.roundTrips++; // A -> B -> A, the price came back to the exact print
                }
            }
            newestAnswer2 = newerAnswer;
            newerAnswer = answer;
            newerAt = updatedAt;
            if (id == 1) break;
        }

        (, int256 lastAnswer,, uint256 lastAt,) = agg.latestRoundData();
        m.last = lastAnswer;
        m.silentNow = lastAt == 0 ? type(uint256).max : openSecondsBetween(lastAt, block.timestamp);
    }

    /// The mapping from measurements to a letter. Pure, so the methodology is
    /// the code and the code is the methodology.
    function letterOf(Metrics memory m) public pure returns (string memory) {
        // Dark right now beats everything: more than a full session of market
        // hours with no print means the feed is not at work today.
        if (m.silentNow > 390 minutes) return "D";

        uint256 w = m.worstSilence;
        uint8 notch;
        if (w <= 30 minutes) notch = 8; // AAA
        else if (w <= 90 minutes) notch = 7; // AA
        else if (w <= 195 minutes) notch = 6; // A     half a session
        else if (w <= 390 minutes) notch = 5; // BBB   a full session
        else if (w <= 780 minutes) notch = 4; // BB    two sessions
        else if (w <= 1560 minutes) notch = 3; // B    a week of half days
        else notch = 2; // CCC

        // A price that keeps walking A -> B -> back to exactly A is a feed
        // showing its plumbing. Investment grade ends where that begins.
        if (m.roundTrips >= 3 && notch > 4) notch = 4;
        else if (m.roundTrips >= 1 && notch > 6) notch = 6;

        // A thin file cannot be prime, the way a borrower with no history
        // cannot be. Half the lookback missing caps the grade.
        if (m.rounds < LOOKBACK / 2 && notch > 6) notch = 6;

}
}
