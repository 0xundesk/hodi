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

contract AAATest is Test {
    // Fixed points on the real calendar, in UTC.
    uint256 constant SEP4_FRI = 1788480000; // 2026-09-04 00:00, a trading Friday
    uint256 constant SEP7_LABOR = 1788739200; // 2026-09-07, Labor Day
    uint256 constant SEP8_TUE = 1788825600; // 2026-09-08, a trading Tuesday
    uint256 constant MAR6_FRI = 1772755200; // 2026-03-06, before the DST switch
    uint256 constant MAR9_MON = 1773014400; // 2026-03-09, after the DST switch

    AAA agency;

    function setUp() public {
        agency = new AAA(new address[](0), new string[](0));
    }

    // ------------------------------------------------------------- calendar

    function test_saturdayIsClosed() public view {
        assertFalse(agency.isOpen(SEP4_FRI + 1 days + 15 hours)); // Saturday 15:00 UTC
    }

    function test_laborDayIsClosed() public view {
        assertFalse(agency.isOpen(SEP7_LABOR + 15 hours), "the agency must know the exchange calendar");
    }

    function test_summerSessionIsHalfPastOneUTC() public view {
        assertFalse(agency.isOpen(SEP8_TUE + 13 hours + 29 minutes));
        assertTrue(agency.isOpen(SEP8_TUE + 13 hours + 30 minutes));
        assertTrue(agency.isOpen(SEP8_TUE + 19 hours + 59 minutes));
        assertFalse(agency.isOpen(SEP8_TUE + 20 hours));
    }

    function test_winterSessionShiftsAnHour() public view {
        // Friday before the March switch runs on winter time.
        assertFalse(agency.isOpen(MAR6_FRI + 13 hours + 30 minutes));
        assertTrue(agency.isOpen(MAR6_FRI + 14 hours + 30 minutes));
        assertTrue(agency.isOpen(MAR6_FRI + 20 hours + 30 minutes));
        // Monday after the switch runs on summer time.
        assertTrue(agency.isOpen(MAR9_MON + 13 hours + 30 minutes));
        assertFalse(agency.isOpen(MAR9_MON + 20 hours + 30 minutes));
    }

    function test_weekendAndHolidayCountForNothing() public view {
        // Friday 19:00 UTC to Tuesday 14:00 UTC, across Labor Day weekend:
        // one open hour left on Friday, nothing Saturday through Monday,
        // thirty open minutes on Tuesday.
        uint256 quiet = agency.openSecondsBetween(SEP4_FRI + 19 hours, SEP8_TUE + 14 hours);
        assertEq(quiet, 1 hours + 30 minutes);
    }

    function test_silenceInsideOneSessionIsCounted() public view {
        assertEq(agency.openSecondsBetween(SEP8_TUE + 15 hours, SEP8_TUE + 18 hours), 3 hours);
    }

    // --------------------------------------------------------------- letters

    function _metrics(uint256 rounds, uint256 worst, uint256 silentNow, uint256 trips)
        internal
        pure
        returns (AAA.Metrics memory m)
    {
        m.rounds = rounds;
        m.worstSilence = worst;
        m.silentNow = silentNow;
        m.roundTrips = trips;
    }

    function test_theLadder() public view {
        assertEq(agency.letterOf(_metrics(300, 20 minutes, 0, 0)), "AAA");
        assertEq(agency.letterOf(_metrics(300, 80 minutes, 0, 0)), "AA");
        assertEq(agency.letterOf(_metrics(300, 3 hours, 0, 0)), "A");
        assertEq(agency.letterOf(_metrics(300, 6 hours, 0, 0)), "BBB");
        assertEq(agency.letterOf(_metrics(300, 12 hours, 0, 0)), "BB");
        assertEq(agency.letterOf(_metrics(300, 25 hours, 0, 0)), "B");
        assertEq(agency.letterOf(_metrics(300, 40 hours, 0, 0)), "CCC");
    }

    function test_darkRightNowIsDefault() public view {
        // A perfect history means nothing if the feed is not at work today.
        assertEq(agency.letterOf(_metrics(300, 10 minutes, 8 hours, 0)), "D");
    }

    function test_roundTripsEndInvestmentGrade() public view {
        assertEq(agency.letterOf(_metrics(300, 10 minutes, 0, 1)), "A");
        assertEq(agency.letterOf(_metrics(300, 10 minutes, 0, 3)), "BB");
    }

    function test_aThinFileCannotBePrime() public view {
        assertEq(agency.letterOf(_metrics(90, 10 minutes, 0, 0)), "A");
    }

    // ------------------------------------------------------- walking rounds

    /// Prints every ten market minutes across a week: the model employee.
    function test_aPunctualFeedGradesAAA() public {
        MockAggregator feed = new MockAggregator();
        for (uint256 day = 0; day < 9; day++) {
            uint256 base = SEP4_FRI - 7 days + day * 1 days;
            for (uint256 minute = 810; minute < 1200; minute += 10) {
                uint256 t = base + minute * 60;
                if (agency.isOpen(t)) feed.push(100e8, t);
            }
        }
        vm.warp(SEP4_FRI - 7 days + 9 days); // just after the last print, off hours
        (string memory letter, AAA.Metrics memory m) = agency.grade(address(feed));
        assertEq(letter, "AAA");
        assertLe(m.worstSilence, 30 minutes);
        assertEq(m.roundTrips, 0);
    }

    /// Same employee, but it slept for four market hours one Wednesday.
    function test_oneLongNapCostsTheGrade() public {
        MockAggregator feed = new MockAggregator();
        uint256 wed = SEP8_TUE + 1 days;
        // Tuesday: every ten minutes, the whole session.
        for (uint256 minute = 810; minute < 1200; minute += 10) {
            feed.push(100e8, SEP8_TUE + minute * 60);
        }
        // Wednesday: one print at the open, then nothing for four hours.
        feed.push(100e8, wed + 810 * 60);
        for (uint256 minute = 810 + 240; minute < 1200; minute += 10) {
            feed.push(100e8, wed + minute * 60);
        }
        vm.warp(wed + 1200 * 60 + 1 hours);
        (string memory letter, AAA.Metrics memory m) = agency.grade(address(feed));
        assertEq(m.worstSilence, 4 hours);
        assertEq(letter, "BBB", "half a session of silence is not investment grade anymore");
    }

    /// Prices that walk away and come back to the exact print.
    function test_roundTripsAreCaught() public {
        MockAggregator feed = new MockAggregator();
        uint256 t = SEP8_TUE + 14 hours;
        int256[7] memory walk = [int256(100e8), 101e8, 100e8, 102e8, 100e8, 103e8, 100e8];
        for (uint256 i = 0; i < 7; i++) {
            feed.push(walk[i], t);
            t += 10 minutes;
        }
        vm.warp(t);
        (, AAA.Metrics memory m) = agency.grade(address(feed));
        assertEq(m.roundTrips, 3);
    }

    function test_reportCardWalksEveryFeed() public {
        MockAggregator feed = new MockAggregator();
        feed.push(100e8, SEP8_TUE + 14 hours);
        address[] memory fs = new address[](1);
        string[] memory ns = new string[](1);
        fs[0] = address(feed);
        ns[0] = "TEST";
        AAA board = new AAA(fs, ns);
        vm.warp(SEP8_TUE + 14 hours + 5 minutes);
        (string[] memory tickers, string[] memory letters, AAA.Metrics[] memory ms) = board.reportCard();
        assertEq(tickers.length, 1);
        assertEq(tickers[0], "TEST");
        assertEq(ms[0].rounds, 1);
        assertTrue(bytes(letters[0]).length > 0);
    }
}
