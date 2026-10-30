import Testing
@testable import AgendaCore

@Suite struct RecurringTaskTests {
    /// Every Monday at 09:00, due by Wednesday, starting 2 November.
    func addWeeklyReview(to agenda: inout Agenda, until: Day? = nil) throws -> TaskID {
        try agenda.addTask(
            "Weekly review",
            plan: Plan(
                start: moment(2026, 11, 2, 9),
                deadline: moment(2026, 11, 4),
                recurrence: Recurrence(.weekly, until: until)
            ),
            at: thursdayBefore
        )
    }

    @Test func completingArchivesTheOccurrenceAndMovesOn() throws { // T5
        var agenda = Agenda()
        let review = try addWeeklyReview(to: &agenda)
        try agenda.complete(review, at: at(2026, 11, 2, 9, 30))

        #expect(agenda.completions.map(\.occurrence) == [Day(2026, 11, 2)])
        #expect(agenda.tasks[review]?.isArchived == false)
        let next = try agenda.schedule(of: review, at: at(2026, 11, 2, 10))
        #expect(next.start == moment(2026, 11, 9, 9))
        #expect(next.deadline == moment(2026, 11, 11))
        #expect(!next.isOverdue)
    }

    @Test func missedOccurrencesDontPileUp() throws { // T7
        var agenda = Agenda()
        let review = try addWeeklyReview(to: &agenda)

        let weeksLater = at(2026, 11, 19)
        let missed = try agenda.schedule(of: review, at: weeksLater)
        #expect(missed.doDate == moment(2026, 11, 2, 9))
        #expect(missed.isOverdue)

        try agenda.complete(review, at: weeksLater)
        #expect(agenda.completions.count == 1)
        #expect(try agenda.schedule(of: review, at: weeksLater).doDate == moment(2026, 11, 23, 9))
    }

    @Test func completingEarlyMovesToTheFollowingOccurrence() throws {
        var agenda = Agenda()
        let review = try addWeeklyReview(to: &agenda)
        try agenda.complete(review, at: at(2026, 10, 31))
        #expect(try agenda.schedule(of: review, at: at(2026, 10, 31)).doDate == moment(2026, 11, 9, 9))
    }

    @Test func theLastOccurrenceArchivesTheTask() throws {
        var agenda = Agenda()
        let review = try addWeeklyReview(to: &agenda, until: Day(2026, 11, 9))
        try agenda.complete(review, at: at(2026, 11, 2))
        #expect(agenda.tasks[review]?.isArchived == false)

        try agenda.complete(review, at: at(2026, 11, 9))
        #expect(agenda.tasks[review]?.archived?.outcome == .done)
        #expect(agenda.completions.count == 2)
    }

    @Test func completingClearsAReschedule() throws { // D5
        var agenda = Agenda()
        let review = try addWeeklyReview(to: &agenda)
        try agenda.reschedule(review, to: moment(2026, 11, 3, 18))
        try agenda.complete(review, at: at(2026, 11, 3, 18, 30))

        #expect(agenda.tasks[review]?.rescheduled == nil)
        #expect(try agenda.schedule(of: review, at: at(2026, 11, 3, 19)).doDate == moment(2026, 11, 9, 9))
    }

    @Test func aRepeatNeedsADateAndAValidInterval() {
        var agenda = Agenda()
        #expect(throws: RuleViolation.recurrenceNeedsDate) {
            try agenda.addTask("Water plants", plan: Plan(recurrence: Recurrence(.daily)), at: thursdayBefore)
        }
        #expect(throws: RuleViolation.invalidRecurrence) {
            try agenda.addTask(
                "Water plants", plan: Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.daily, every: 0)),
                at: thursdayBefore
            )
        }
    }
}
