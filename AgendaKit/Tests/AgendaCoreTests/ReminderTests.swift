import Testing
@testable import AgendaCore

@Suite struct ReminderTests {
    /// Dentist on Monday 2 November at 10:00.
    func addDentist(to agenda: inout Agenda, start: Moment = moment(2026, 11, 2, 10)) throws -> TaskID {
        try agenda.addTask("Dentist", plan: Plan(start: start), at: thursdayBefore)
    }

    func walls(_ agenda: Agenda, _ id: TaskID, at context: Context = thursdayBefore, in zone: String = madrid) -> [String] {
        agenda.reminderTimes(for: id, at: context).map { wall($0.date, in: zone) }
    }

    @Test func theFirstReminderIsTheMainOne() throws { // R1
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        let main = try agenda.addReminder(.alarm, .minutes(-30), to: dentist)
        let other = try agenda.addReminder(.sticky, .days(-1), to: dentist)

        #expect(agenda.tasks[dentist]?.mainReminder?.id == main)
        #expect(agenda.tasks[dentist]?.reminders.map(\.id) == [other])
        let times = agenda.reminderTimes(for: dentist, at: thursdayBefore)
        #expect(times.map(\.isMain) == [true, false])
        #expect(times.map(\.kind) == [.alarm, .sticky])
    }

    @Test func otherRemindersCountFromTheMainOne() throws { // R3, R4
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        try agenda.addReminder(.sticky, .on(days: -1, at: TimeOfDay(18)), to: dentist)
        try agenda.addReminder(.sticky, .days(-1), to: dentist)
        try agenda.addReminder(.alarm, .minutes(-60), to: dentist)

        #expect(walls(agenda, dentist) == ["2026-11-01 18:00", "2026-10-31 18:00", "2026-11-01 17:00"])
    }

    @Test func remindersFollowAReschedule() throws { // D2
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        try agenda.addReminder(.alarm, .minutes(-30), to: dentist)
        try agenda.addReminder(.sticky, .days(-1), to: dentist)
        #expect(walls(agenda, dentist) == ["2026-11-02 09:30", "2026-11-01 09:30"])

        try agenda.reschedule(dentist, to: moment(2026, 11, 5, 15))
        #expect(walls(agenda, dentist) == ["2026-11-05 14:30", "2026-11-04 14:30"])
    }

    @Test func dayOffsetsKeepTheClockTimeAcrossDaylightSaving() throws {
        // New York turns its clocks back during the night of 31 October to 1 November 2026.
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda, start: moment(2026, 11, 1))
        try agenda.addReminder(.alarm, .on(days: 0, at: TimeOfDay(9)), to: dentist)
        try agenda.addReminder(.sticky, .days(-1), to: dentist)
        try agenda.addReminder(.sticky, .minutes(-24 * 60), to: dentist)

        let newYorkContext = at(2026, 10, 29, in: newYork)
        #expect(walls(agenda, dentist, at: newYorkContext, in: newYork)
            == ["2026-11-01 09:00", "2026-10-31 09:00", "2026-10-31 10:00"])
    }

    @Test func remindersFollowTheUserAcrossTimeZones() throws { // T13
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        try agenda.addReminder(.alarm, .minutes(-30), to: dentist)

        #expect(walls(agenda, dentist, at: at(2026, 10, 29, in: madrid), in: madrid) == ["2026-11-02 09:30"])
        #expect(walls(agenda, dentist, at: at(2026, 10, 29, in: tokyo), in: tokyo) == ["2026-11-02 09:30"])
    }

    @Test func aWholeDayCountsFromNineInTheMorning() throws { // R10
        var agenda = Agenda()
        let tidy = try addDentist(to: &agenda, start: moment(2026, 11, 2))
        try agenda.addReminder(.sticky, .minutes(-30), to: tidy)
        #expect(walls(agenda, tidy) == ["2026-11-02 08:30"])
    }

    @Test func aReminderOnAnUndatedTaskSetsItsStart() throws { // R8
        var agenda = Agenda()
        let idea = try agenda.addTask("Book flights", at: thursdayBefore)
        try agenda.addReminder(.alarm, on: moment(2026, 11, 5, 8), to: idea, at: thursdayBefore)

        #expect(agenda.tasks[idea]?.plan.start == moment(2026, 11, 5, 8))
        #expect(walls(agenda, idea) == ["2026-11-05 08:00"])
    }

    @Test func remindersAtAGivenDayAndTime() throws {
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        try agenda.addReminder(.sticky, on: moment(2026, 11, 1, 20), to: dentist, at: thursdayBefore)
        try agenda.addReminder(.sticky, on: moment(2026, 10, 31, 9), to: dentist, at: thursdayBefore)
        #expect(walls(agenda, dentist) == ["2026-11-01 20:00", "2026-10-31 09:00"])

        // Both still follow the task when it moves (D2).
        try agenda.reschedule(dentist, to: moment(2026, 11, 3, 10))
        #expect(walls(agenda, dentist) == ["2026-11-02 20:00", "2026-11-01 09:00"])
    }

    @Test func removingTheMainReminderPromotesTheEarliest() throws { // R9
        var agenda = Agenda()
        let dentist = try addDentist(to: &agenda)
        let main = try agenda.addReminder(.alarm, .minutes(-30), to: dentist)
        try agenda.addReminder(.sticky, .days(-1), to: dentist)
        let earliest = try agenda.addReminder(.sticky, .days(-2), to: dentist)

        try agenda.removeReminder(main, from: dentist, at: thursdayBefore)
        #expect(agenda.tasks[dentist]?.mainReminder?.id == earliest)
        #expect(walls(agenda, dentist) == ["2026-10-31 09:30", "2026-11-01 09:30"])
    }

    @Test func lockedAndArchivedTasksHaveNoReminders() throws { // S9, T2
        var agenda = Agenda()
        let first = try addDentist(to: &agenda)
        let second = try addDentist(to: &agenda, start: moment(2026, 11, 3, 10))
        try agenda.link(first, then: second)
        try agenda.addReminder(.alarm, .minutes(-30), to: first)
        try agenda.addReminder(.alarm, .minutes(-30), to: second)

        #expect(agenda.reminderTimes(for: second, at: thursdayBefore).isEmpty)
        try agenda.complete(first, at: thursdayBefore)
        #expect(agenda.reminderTimes(for: first, at: thursdayBefore).isEmpty)
        #expect(walls(agenda, second) == ["2026-11-03 09:30"])
    }

    @Test func keysChangeWithEachOccurrence() throws {
        var agenda = Agenda()
        let weekly = try agenda.addTask(
            "Bins out", plan: Plan(start: moment(2026, 11, 2, 20), recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        try agenda.addReminder(.sticky, .minutes(0), to: weekly)
        let before = agenda.reminderTimes(for: weekly, at: thursdayBefore)
        #expect(before == agenda.reminderTimes(for: weekly, at: thursdayBefore))

        try agenda.complete(weekly, at: at(2026, 11, 2, 21))
        let after = agenda.reminderTimes(for: weekly, at: at(2026, 11, 2, 21))
        #expect(after[0].key != before[0].key)
        #expect(wall(after[0].date) == "2026-11-09 20:00")
    }
}
