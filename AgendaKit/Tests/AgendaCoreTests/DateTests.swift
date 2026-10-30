import Foundation
import Testing
@testable import AgendaCore

@Suite struct DateTests {
    @Test func dayArithmeticCrossesMonthsYearsAndLeapDays() {
        #expect(Day(2026, 12, 31).adding(days: 1) == Day(2027, 1, 1))
        #expect(Day(2028, 2, 28).adding(days: 1) == Day(2028, 2, 29))
        #expect(Day(2026, 3, 1).adding(days: -1) == Day(2026, 2, 28))
        #expect(Day(2026, 11, 2).days(to: Day(2026, 11, 9)) == 7)
        #expect(Day(2026, 11, 9).days(to: Day(2026, 11, 2)) == -7)
        #expect(Day(2026, 11, 2).weekday == 2)
    }

    @Test func dayArithmeticIgnoresDaylightSaving() {
        // Madrid turns its clocks back on 25 October 2026, New York on 1 November.
        #expect(Day(2026, 10, 24).days(to: Day(2026, 10, 26)) == 2)
        #expect(Day(2026, 10, 31).adding(days: 2) == Day(2026, 11, 2))
    }

    @Test func dayOfAnInstantDependsOnTheTimeZone() {
        let lateInMadrid = at(2026, 11, 2, 23, 30).now
        #expect(Day(lateInMadrid, in: calendar(madrid)) == Day(2026, 11, 2))
        #expect(Day(lateInMadrid, in: calendar(tokyo)) == Day(2026, 11, 3))
    }

    @Test func momentsAreFloating() {
        let call = moment(2026, 11, 3, 10)
        #expect(wall(call.start(in: calendar(madrid)), in: madrid) == "2026-11-03 10:00")
        #expect(wall(call.start(in: calendar(tokyo)), in: tokyo) == "2026-11-03 10:00")
        #expect(call.start(in: calendar(madrid)) != call.start(in: calendar(tokyo)))
    }

    @Test func aWholeDayLastsUntilMidnight() {
        let tuesday = moment(2026, 11, 3)
        #expect(wall(tuesday.start(in: calendar())) == "2026-11-03 00:00")
        #expect(wall(tuesday.end(in: calendar())) == "2026-11-04 00:00")
        #expect(wall(moment(2026, 11, 3, 17).end(in: calendar())) == "2026-11-03 17:00")
    }

    @Test func aTimeSkippedByDaylightSavingMovesForward() {
        // New York skips 02:00 to 03:00 on 8 March 2026.
        let skipped = moment(2026, 3, 8, 2, 30)
        let parts = calendar(newYork).dateComponents([.day, .hour], from: skipped.start(in: calendar(newYork)))
        #expect(parts.day == 8)
        #expect(parts.hour == 3)
    }

    @Test func aDeadlineAndAStartOnTheSameDayDontConflict() {
        #expect(!moment(2026, 11, 3).isLater(than: moment(2026, 11, 3, 9)))
        #expect(!moment(2026, 11, 3, 17).isLater(than: moment(2026, 11, 3)))
        #expect(moment(2026, 11, 3, 10).isLater(than: moment(2026, 11, 3, 9)))
        #expect(moment(2026, 11, 4).isLater(than: moment(2026, 11, 3, 23)))
    }
}
