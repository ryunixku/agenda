import Testing
@testable import AgendaCore

@Suite struct RescheduleTests {
    let monday10 = moment(2026, 11, 2, 10)
    let tuesday10 = moment(2026, 11, 3, 10)

    @Test func reschedulingNeverChangesThePlan() throws { // D1
        var agenda = Agenda()
        let call = try agenda.addTask("Call the bank", plan: Plan(start: monday10), at: thursdayBefore)
        try agenda.reschedule(call, to: tuesday10)

        #expect(agenda.tasks[call]?.plan.start == monday10)
        let tuesday = try agenda.schedule(of: call, at: at(2026, 11, 3, 9))
        #expect(tuesday.doDate == tuesday10)
        #expect(tuesday.plannedStart == monday10)
        #expect(tuesday.isRescheduled)
        #expect(!tuesday.isOverdue)
    }

    @Test func aMissedOneOffTaskIsOverdueSinceItsNewDate() throws { // D3, D5
        var agenda = Agenda()
        let call = try agenda.addTask("Call the bank", plan: Plan(start: monday10), at: thursdayBefore)
        try agenda.reschedule(call, to: tuesday10)

        let lateTuesday = try agenda.schedule(of: call, at: at(2026, 11, 3, 23, 59))
        #expect(!lateTuesday.isOverdue)

        let wednesday = try agenda.schedule(of: call, at: at(2026, 11, 4, 0, 1))
        #expect(wednesday.doDate == tuesday10)
        #expect(wednesday.isRescheduled)
        #expect(wednesday.isOverdue)
        #expect(wednesday.plannedStart == monday10)
    }

    @Test func aMissedRecurringOccurrenceGoesBackToItsSchedule() throws { // D3, D5
        var agenda = Agenda()
        let weekly = try agenda.addTask(
            "Call mum", plan: Plan(start: monday10, recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        try agenda.reschedule(weekly, to: tuesday10)

        let tuesday = try agenda.schedule(of: weekly, at: at(2026, 11, 3, 23))
        #expect(tuesday.doDate == tuesday10)

        let wednesday = try agenda.schedule(of: weekly, at: at(2026, 11, 4, 0, 1))
        #expect(wednesday.doDate == monday10)
        #expect(!wednesday.isRescheduled)
        #expect(wednesday.isOverdue)
    }

    @Test func aPresetLeavesTheDeadlineAlone() throws { // D4, D7
        var agenda = Agenda()
        let report = try agenda.addTask(
            "Send report", plan: Plan(start: monday10, deadline: moment(2026, 11, 3)), at: thursdayBefore
        )
        try agenda.reschedule(report, to: .nextWeek, at: at(2026, 11, 2, 9))

        let wednesday = try agenda.schedule(of: report, at: at(2026, 11, 4))
        #expect(wednesday.doDate == moment(2026, 11, 9, 10))
        #expect(wednesday.deadline == moment(2026, 11, 3))
        #expect(wednesday.isPastDeadline)
        #expect(!wednesday.isOverdue)
    }

    @Test func theDeadlineCanMoveInTheSameStep() throws { // D4, D8
        var agenda = Agenda()
        let report = try agenda.addTask(
            "Send report", plan: Plan(start: monday10, deadline: moment(2026, 11, 3)), at: thursdayBefore
        )
        try agenda.reschedule(report, to: moment(2026, 11, 9, 10), deadline: moment(2026, 11, 10))

        let wednesday = try agenda.schedule(of: report, at: at(2026, 11, 4))
        #expect(wednesday.deadline == moment(2026, 11, 10))
        #expect(wednesday.plannedDeadline == moment(2026, 11, 3))
        #expect(!wednesday.isPastDeadline)
        #expect(agenda.tasks[report]?.plan.deadline == moment(2026, 11, 3))
    }

    @Test func aMovedDeadlineCantComeBeforeTheNewDate() throws {
        var agenda = Agenda()
        let report = try agenda.addTask("Send report", plan: Plan(start: monday10), at: thursdayBefore)
        #expect(throws: RuleViolation.deadlineBeforeStart) {
            try agenda.reschedule(report, to: moment(2026, 11, 9), deadline: moment(2026, 11, 8))
        }
    }

    @Test func presets() throws { // D6
        var agenda = Agenda()
        let timed = try agenda.addTask("Call", plan: Plan(start: monday10), at: thursdayBefore)
        let wholeDay = try agenda.addTask("Tidy up", plan: Plan(start: moment(2026, 11, 2)), at: thursdayBefore)
        let monday = at(2026, 11, 2, 8)

        #expect(try agenda.moment(for: .tonight, task: timed, at: monday) == moment(2026, 11, 2, 19))
        #expect(try agenda.moment(for: .tomorrow, task: timed, at: monday) == moment(2026, 11, 3, 10))
        #expect(try agenda.moment(for: .nextWeek, task: timed, at: monday) == moment(2026, 11, 9, 10))
        #expect(try agenda.moment(for: .tomorrow, task: wholeDay, at: monday) == moment(2026, 11, 3))
    }

    @Test func undatedTasksCanBeRescheduled() throws {
        var agenda = Agenda()
        let idea = try agenda.addTask("Look into solar panels", at: thursdayBefore)
        try agenda.reschedule(idea, to: .tomorrow, at: thursdayBefore)
        #expect(try agenda.schedule(of: idea, at: thursdayBefore).doDate == moment(2026, 10, 30))
    }
}
