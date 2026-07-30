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

}
