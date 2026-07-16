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

        string[9] memory letters = ["", "D", "CCC", "B", "BB", "BBB", "A", "AA", "AAA"];
        return letters[notch];
    }

    // ------------------------------------------------- the exchange calendar

    /// Market-hours seconds inside [from, to]. Weekends, NYSE holidays and
    /// everything outside the regular session count for nothing.
    function openSecondsBetween(uint256 from, uint256 to) public pure returns (uint256 total) {
        if (to <= from) return 0;
        uint256 day = from / 1 days;
        uint256 lastDay = to / 1 days;
        for (uint256 guard = 0; day <= lastDay && guard < 500; (day++, guard++)) {
            (uint256 sessionStart, uint256 sessionEnd) = _session(day);
            if (sessionStart == 0) continue;
            uint256 lo = from > sessionStart ? from : sessionStart;
            uint256 hi = to < sessionEnd ? to : sessionEnd;
            if (hi > lo) total += hi - lo;
        }
    }

    function isOpen(uint256 t) public pure returns (bool) {
        (uint256 s, uint256 e) = _session(t / 1 days);
        return t >= s && t < e && s != 0;
    }

    /// The regular session for a day (as a unix-day number), or (0, 0) when
    /// the market does not open at all.
    function _session(uint256 day) internal pure returns (uint256 start, uint256 end) {
        uint256 dow = (day + 3) % 7; // 0 = Monday
        if (dow >= 5) return (0, 0);

        (uint256 y, uint256 mo, uint256 d) = _civil(day);
        if (_holiday(y, mo, d)) return (0, 0);

        bool dst = _dst(y, mo, d);
        // 9:30 to 16:00 New York, expressed in UTC.
        uint256 openMinute = dst ? 13 * 60 + 30 : 14 * 60 + 30;
        uint256 closeMinute = dst ? 20 * 60 : 21 * 60;
        start = day * 1 days + openMinute * 60;
        end = day * 1 days + closeMinute * 60;
    }

    /// Full NYSE closures. The list is part of the methodology and a new
    /// deployment is a new edition, the way a calendar gets a new year.
    function _holiday(uint256 y, uint256 mo, uint256 d) internal pure returns (bool) {
        uint256 date = y * 10000 + mo * 100 + d;
        uint32[20] memory closed = [
            // 2026
            uint32(20260101), // New Year's Day
            20260119, // Martin Luther King Jr. Day
            20260216, // Washington's Birthday
            20260403, // Good Friday
            20260525, // Memorial Day
            20260619, // Juneteenth
            20260703, // Independence Day, observed
            20260907, // Labor Day
            20261126, // Thanksgiving
            20261225, // Christmas
            // 2027
            20270101,
            20270118,
            20270215,
            20270326,
            20270531,
            20270618, // Juneteenth, observed
            20270705, // Independence Day, observed
            20270906,
            20271125,
            20271224 // Christmas, observed
        ];
        for (uint256 i = 0; i < closed.length; i++) {
            if (closed[i] == date) return true;
        }
        return false;
    }

    /// US daylight saving: from the second Sunday of March to the first
    /// Sunday of November. Transitions land on Sundays, when the market is
    /// closed, so day granularity is exact for every trading day.
    function _dst(uint256 y, uint256 mo, uint256 d) internal pure returns (bool) {
        if (mo > 3 && mo < 11) return true;
        if (mo < 3 || mo > 11) return false;
        if (mo == 3) {
            uint256 firstDow = (_days(y, 3, 1) + 4) % 7; // 0 = Sunday
            uint256 firstSunday = 1 + ((7 - firstDow) % 7);
            return d >= firstSunday + 7;
        }
        uint256 novDow = (_days(y, 11, 1) + 4) % 7;
        uint256 novSunday = 1 + ((7 - novDow) % 7);
        return d < novSunday;
    }

    // Howard Hinnant's civil date algorithms.
}
