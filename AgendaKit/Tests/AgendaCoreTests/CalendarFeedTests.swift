import Testing
@testable import AgendaCore

@Suite struct CalendarFeedTests {
    @Test func aTaskWithAStartAndADeadlineIsASpan() throws { // K1, K3
        var agenda = Agenda()
        try agenda.addTask("Paint the hall", plan: Plan(start: moment(2026, 11, 2), deadline: moment(2026, 11, 4)), at: thursdayBefore)
        let entries = agenda.calendar(from: Day(2026, 11, 3), through: Day(2026, 11, 3), at: thursdayBefore)
        #expect(entries.count == 1)
        #expect(entries[0].isSpan)
        #expect(entries[0].covers(Day(2026, 11, 3)))
        #expect(!entries[0].covers(Day(2026, 11, 5)))
    }

    @Test func aRescheduledTaskShowsAtItsNewDateWithItsPlan() throws { // K3
        var agenda = Agenda()
        let call = try agenda.addTask("Call the bank", plan: Plan(start: moment(2026, 11, 2, 10)), at: thursdayBefore)
        try agenda.reschedule(call, to: moment(2026, 11, 3, 10))
        let entries = agenda.calendar(from: Day(2026, 11, 1), through: Day(2026, 11, 7), at: thursdayBefore)
        #expect(entries.map(\.start) == [moment(2026, 11, 3, 10)])
        #expect(entries[0].plannedDoDate == moment(2026, 11, 2, 10))
        #expect(entries[0].isRescheduled)
    }

    @Test func recurringTasksShowEveryOccurrenceFromTheCurrentOne() throws {
        var agenda = Agenda()
        let bins = try agenda.addTask(
            "Bins out", plan: Plan(start: moment(2026, 11, 2, 20), recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        try agenda.complete(bins, at: at(2026, 11, 2, 21))
        let entries = agenda.calendar(from: Day(2026, 11, 1), through: Day(2026, 11, 30), at: at(2026, 11, 3))
        #expect(entries.compactMap(\.occurrence) == [Day(2026, 11, 9), Day(2026, 11, 16), Day(2026, 11, 23), Day(2026, 11, 30)])
        #expect(Set(entries.map(\.id)).count == 4)
    }

    @Test func undatedAndArchivedTasksAreLeftOut() throws {
        var agenda = Agenda()
        try agenda.addTask("Someday", at: thursdayBefore)
        let done = try agenda.addTask("Done", plan: Plan(start: moment(2026, 11, 2)), at: thursdayBefore)
        try agenda.complete(done, at: thursdayBefore)
        #expect(agenda.calendar(from: Day(2026, 11, 1), through: Day(2026, 11, 30), at: thursdayBefore).isEmpty)
    }
}
