import Testing
@testable import AgendaCore

@Suite struct SequenceTests {
    func addTask(_ title: String, _ agenda: inout Agenda, start: Moment? = nil, deadline: Moment? = nil) throws -> TaskID {
        try agenda.addTask(title, plan: Plan(start: start, deadline: deadline), at: thursdayBefore)
    }

    @Test func theNextTaskIsLockedUntilThePreviousIsDone() throws { // S4, S12
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda)
        let book = try addTask("Book the plumber", &agenda)
        try agenda.link(quote, then: book)

        #expect(agenda.isLocked(book))
        #expect(throws: RuleViolation.locked) { try agenda.complete(book, at: thursdayBefore) }
        try agenda.complete(quote, at: thursdayBefore)
        #expect(!agenda.isLocked(book))
        try agenda.complete(book, at: thursdayBefore)
    }

    @Test func aPredecessorClosedAnyWayUnlocks() throws { // S12
        var agenda = Agenda()
        let renovation = agenda.addProject("Renovation")
        let quote = try agenda.addTask("Get a quote", in: renovation, at: thursdayBefore)
        let book = try addTask("Book the plumber", &agenda)
        try agenda.link(quote, then: book)

        try agenda.completeProject(renovation, at: thursdayBefore)
        #expect(agenda.tasks[quote]?.archived?.outcome == .notDone)
        #expect(!agenda.isLocked(book))
    }

    @Test func aDeadlineCantPassTheNextStart() throws { // S5
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, deadline: moment(2026, 11, 6))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 5))
        #expect(throws: RuleViolation.sequenceDateConflict(book)) { try agenda.link(quote, then: book) }
    }

    @Test func handingOverOnTheSameDayIsFine() throws { // S5
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, deadline: moment(2026, 11, 5))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 5, 9))
        try agenda.link(quote, then: book)
    }

    @Test func anEditThatBreaksTheOrderIsBlocked() throws { // S6
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, deadline: moment(2026, 11, 4))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 5))
        try agenda.link(quote, then: book)

        #expect(throws: RuleViolation.sequenceDateConflict(book)) {
            try agenda.setPlan(quote, to: Plan(deadline: moment(2026, 11, 7)))
        }
        #expect(throws: RuleViolation.sequenceDateConflict(quote)) {
            try agenda.setPlan(book, to: Plan(start: moment(2026, 11, 3)))
        }
        #expect(agenda.tasks[quote]?.plan.deadline == moment(2026, 11, 4))
    }

    @Test func shiftingTheNextTasksFixesTheOrder() throws { // S6
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, deadline: moment(2026, 11, 4))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 5), deadline: moment(2026, 11, 6))
        let pay = try addTask("Pay", &agenda, start: moment(2026, 11, 7, 10))
        try agenda.link(quote, then: book)
        try agenda.link(book, then: pay)

        try agenda.setPlan(quote, to: Plan(deadline: moment(2026, 11, 7)), shiftingNext: true)
        #expect(agenda.tasks[book]?.plan.start == moment(2026, 11, 7))
        #expect(agenda.tasks[book]?.plan.deadline == moment(2026, 11, 8))
        #expect(agenda.tasks[pay]?.plan.start == moment(2026, 11, 8, 10))
    }

    @Test func shiftingResolvesATimeClashOnTheSameDay() throws { // S6
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, deadline: moment(2026, 11, 4, 12))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 4, 13))
        try agenda.link(quote, then: book)

        try agenda.setPlan(quote, to: Plan(deadline: moment(2026, 11, 4, 15)), shiftingNext: true)
        #expect(agenda.tasks[book]?.plan.start == moment(2026, 11, 5, 13))
    }

    @Test func recurringTasksCantBeInASequence() throws { // S7
        var agenda = Agenda()
        let weekly = try agenda.addTask(
            "Shop", plan: Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        let cook = try addTask("Cook", &agenda)
        #expect(throws: RuleViolation.recurringInSequence) { try agenda.link(weekly, then: cook) }

        let plan = try addTask("Plan meals", &agenda)
        try agenda.link(plan, then: cook)
        #expect(throws: RuleViolation.recurringInSequence) {
            try agenda.setPlan(cook, to: Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.weekly)))
        }
    }

    @Test func subtasksCanBeSteps() throws { // S8, S13
        var agenda = Agenda()
        let move = try addTask("Move flat", &agenda)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let load = try agenda.addSubtask("Load the van", to: move, at: thursdayBefore)
        try agenda.link(pack, then: load)
        #expect(agenda.isLocked(load))

        let trip = try addTask("Trip", &agenda)
        let passports = try agenda.addSubtask("Passports", to: trip, at: thursdayBefore)
        #expect(throws: RuleViolation.sequenceAcrossParents) { try agenda.link(load, then: passports) }
        #expect(throws: RuleViolation.sequenceAcrossParents) { try agenda.link(trip, then: passports) }
    }

    @Test func aLockedParentLocksItsSubtasks() throws {
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda)
        let renovate = try addTask("Renovate", &agenda)
        let paint = try agenda.addSubtask("Paint", to: renovate, at: thursdayBefore)
        try agenda.link(quote, then: renovate)

        #expect(agenda.isLocked(paint))
        #expect(throws: RuleViolation.locked) { try agenda.complete(paint, at: thursdayBefore) }
    }

    @Test func reschedulingPastTheNextStartIsAllowed() throws { // S11
        var agenda = Agenda()
        let quote = try addTask("Get a quote", &agenda, start: moment(2026, 11, 2), deadline: moment(2026, 11, 4))
        let book = try addTask("Book the plumber", &agenda, start: moment(2026, 11, 5))
        try agenda.link(quote, then: book)

        try agenda.reschedule(quote, to: moment(2026, 11, 9), deadline: moment(2026, 11, 10))
        #expect(agenda.isLocked(book))
    }

    @Test func noBranchesAndNoLoops() throws { // S13
        var agenda = Agenda()
        let a = try addTask("A", &agenda)
        let b = try addTask("B", &agenda)
        let c = try addTask("C", &agenda)
        try agenda.link(a, then: b)
        try agenda.link(b, then: c)

        #expect(throws: RuleViolation.alreadyLinked) { try agenda.link(a, then: c) }
        #expect(throws: RuleViolation.sequenceCycle) { try agenda.link(c, then: a) }
        #expect(throws: RuleViolation.sequenceCycle) { try agenda.link(a, then: a) }
    }

    @Test func theNowScreenShowsWhatCanBeDoneToday() throws { // S9
        var agenda = Agenda()
        let overdue = try addTask("Overdue", &agenda, start: moment(2026, 10, 27))
        let today = try addTask("Today", &agenda, start: moment(2026, 10, 29, 9))
        _ = try addTask("Later", &agenda, start: moment(2026, 11, 2))
        _ = try addTask("Undated", &agenda)
        let locked = try addTask("Locked", &agenda, start: moment(2026, 10, 29))
        try agenda.link(today, then: locked)
        let done = try addTask("Done", &agenda, start: moment(2026, 10, 29))
        try agenda.complete(done, at: thursdayBefore)

        #expect(agenda.actionable(at: thursdayBefore).map(\.id) == [overdue, today])
    }
}
