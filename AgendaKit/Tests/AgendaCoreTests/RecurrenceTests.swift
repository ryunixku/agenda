import Testing
@testable import AgendaCore

/// T6: repeats follow a fixed schedule.
@Suite struct RecurrenceTests {
    func days(_ rule: Recurrence, first: Day, from start: Day, through end: Day) -> [String] {
        rule.occurrences(from: start, through: end, first: first, firstWeekday: 2).map(\.description)
    }

    @Test func everyFewDays() {
        let rule = Recurrence(.daily, every: 3)
        #expect(days(rule, first: Day(2026, 11, 2), from: Day(2026, 11, 1), through: Day(2026, 11, 12))
            == ["2026-11-02", "2026-11-05", "2026-11-08", "2026-11-11"])
    }

    @Test func severalWeekdaysEveryOtherWeek() {
        let rule = Recurrence(.weekly, every: 2, on: [2, 4, 6]) // Monday, Wednesday, Friday
        #expect(days(rule, first: Day(2026, 11, 2), from: Day(2026, 11, 2), through: Day(2026, 11, 22))
            == ["2026-11-02", "2026-11-04", "2026-11-06", "2026-11-16", "2026-11-18", "2026-11-20"])
    }

    @Test func theFirstDayAlwaysCounts() {
        let mondays = Recurrence(.weekly, on: [2])
        #expect(days(mondays, first: Day(2026, 11, 4), from: Day(2026, 11, 1), through: Day(2026, 11, 16))
            == ["2026-11-04", "2026-11-09", "2026-11-16"])
    }

    @Test func theLastDayOfTheMonthDoesNotDrift() {
        let rule = Recurrence(.monthly)
        #expect(days(rule, first: Day(2026, 1, 31), from: Day(2026, 1, 1), through: Day(2026, 5, 31))
            == ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-05-31"])
    }

    @Test func aLeapDayComesBackInLeapYears() {
        let rule = Recurrence(.yearly)
        #expect(days(rule, first: Day(2028, 2, 29), from: Day(2028, 1, 1), through: Day(2032, 12, 31))
            == ["2028-02-29", "2029-02-28", "2030-02-28", "2031-02-28", "2032-02-29"])
    }

    @Test func untilEndsTheSeries() {
        let rule = Recurrence(.daily, until: Day(2026, 11, 4))
        #expect(rule.occurrence(after: Day(2026, 11, 3), first: Day(2026, 11, 2), firstWeekday: 2) == Day(2026, 11, 4))
        #expect(rule.occurrence(after: Day(2026, 11, 4), first: Day(2026, 11, 2), firstWeekday: 2) == nil)
    }

    @Test func nextOccurrenceYearsLater() {
        let quarterly = Recurrence(.monthly, every: 3)
        #expect(quarterly.occurrence(after: Day(2030, 6, 15), first: Day(2026, 1, 31), firstWeekday: 2) == Day(2030, 7, 31))
    }
}
