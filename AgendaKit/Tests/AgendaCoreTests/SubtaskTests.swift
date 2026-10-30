import Testing
@testable import AgendaCore

@Suite struct SubtaskTests {
    @Test func subtasksAreOneLevelDeep() throws { // S1
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        #expect(throws: RuleViolation.nestingTooDeep) {
            try agenda.addSubtask("Buy boxes", to: pack, at: thursdayBefore)
        }
    }

    @Test func finishingEverySubtaskFinishesTheParent() throws { // S2
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let clean = try agenda.addSubtask("Clean", to: move, at: thursdayBefore)

        try agenda.complete(pack, at: thursdayBefore)
        #expect(agenda.tasks[move]?.isArchived == false)
        try agenda.complete(clean, at: thursdayBefore)
        #expect(agenda.tasks[move]?.archived?.outcome == .done)
    }

    @Test func finishingTheParentArchivesOpenSubtasksAsNotDone() throws { // S3, T8
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let clean = try agenda.addSubtask("Clean", to: move, at: thursdayBefore)
        try agenda.complete(pack, at: thursdayBefore)

        try agenda.complete(move, at: thursdayBefore)
        #expect(agenda.tasks[move]?.archived?.outcome == .done)
        #expect(agenda.tasks[pack]?.archived?.outcome == .done)
        #expect(agenda.tasks[clean]?.archived?.outcome == .notDone)
    }

    @Test func finishingTheParentCanMarkSubtasksDone() throws { // S3
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let clean = try agenda.addSubtask("Clean", to: move, at: thursdayBefore)
        try agenda.complete(move, openSubtasks: .markDone, at: thursdayBefore)
        #expect(agenda.tasks[clean]?.archived?.outcome == .done)
    }

    @Test func recurringTasksHaveNoSubtasks() throws { // S14
        var agenda = Agenda()
        let weekly = try agenda.addTask(
            "Clean house", plan: Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        #expect(throws: RuleViolation.recurringSubtasks) {
            try agenda.addSubtask("Kitchen", to: weekly, at: thursdayBefore)
        }

        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let repeating = Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.weekly))
        #expect(throws: RuleViolation.recurringSubtasks) { try agenda.setPlan(pack, to: repeating) }
        #expect(throws: RuleViolation.recurringSubtasks) { try agenda.setPlan(move, to: repeating) }
    }

    @Test func subtasksMoveWithTheirParent() throws {
        var agenda = Agenda()
        let home = agenda.addList("Home")
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        #expect(agenda.tasks[pack]?.container == agenda.inbox)

        try agenda.move(move, to: home)
        #expect(agenda.tasks[pack]?.container == home)
        #expect(throws: RuleViolation.subtaskMovesWithParent) { try agenda.move(pack, to: agenda.inbox) }
    }
}
