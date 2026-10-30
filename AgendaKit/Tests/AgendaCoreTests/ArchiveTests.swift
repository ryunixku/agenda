import Testing
@testable import AgendaCore

@Suite struct ArchiveTests {
    @Test func archivedTasksAreReadOnly() throws { // T2
        var agenda = Agenda()
        let task = try agenda.addTask("Renew passport", at: thursdayBefore)
        try agenda.complete(task, at: thursdayBefore)

        #expect(throws: RuleViolation.archived) { try agenda.rename(task, to: "Renew ID") }
        #expect(throws: RuleViolation.archived) { try agenda.setPlan(task, to: Plan(start: moment(2026, 11, 2))) }
        #expect(throws: RuleViolation.archived) { try agenda.reschedule(task, to: moment(2026, 11, 2)) }
        #expect(throws: RuleViolation.archived) { try agenda.addNote("Took 3 weeks", to: .task(task), at: thursdayBefore) }
        #expect(throws: RuleViolation.archived) { try agenda.complete(task, at: thursdayBefore) }
    }

    @Test func aCloneIsANewActiveTask() throws { // T3, T12
        var agenda = Agenda()
        let trip = try agenda.addTask(
            "Pack for trip", plan: Plan(start: moment(2026, 11, 6, 18)), at: thursdayBefore
        )
        try agenda.addReminder(.alarm, .minutes(-60), to: trip)
        try agenda.addNote("Don't forget chargers", to: .task(trip), at: thursdayBefore)
        let photo = try agenda.addBlob(.photo, to: trip)
        let clothes = try agenda.addSubtask("Clothes", to: trip, at: thursdayBefore)
        let bag = try agenda.addSubtask("Close the bag", to: trip, at: thursdayBefore)
        try agenda.link(clothes, then: bag)
        try agenda.reschedule(trip, to: moment(2026, 11, 7, 9))
        try agenda.complete(trip, at: at(2026, 11, 7))

        let cloned = try agenda.clone(trip, at: at(2026, 12, 1))
        let copy = try #require(agenda.tasks[cloned.task])
        #expect(copy.id != trip)
        #expect(!copy.isArchived)
        #expect(copy.clonedFrom == trip)
        #expect(copy.title == "Pack for trip")
        #expect(copy.plan == Plan(start: moment(2026, 11, 6, 18)))
        #expect(copy.rescheduled == nil)
        #expect(copy.mainReminder?.offset == .minutes(-60))
        #expect(copy.notes.map(\.text) == ["Don't forget chargers"])
        #expect(copy.blobs.map(\.id) == [cloned.blobs[photo]!])

        let steps = agenda.subtasks(of: cloned.task)
        #expect(steps.map(\.title) == ["Clothes", "Close the bag"])
        #expect(steps.allSatisfy { !$0.isArchived })
        #expect(steps[1].previous == steps[0].id)
        #expect(agenda.tasks[trip]?.isArchived == true)
    }

    @Test func aCloneFromAFinishedProjectGoesToTheInbox() throws { // T12
        var agenda = Agenda()
        let wedding = agenda.addProject("Wedding")
        let venue = try agenda.addTask("Book venue", in: wedding, at: thursdayBefore)
        try agenda.completeProject(wedding, at: thursdayBefore)

        let cloned = try agenda.clone(venue, at: thursdayBefore)
        #expect(agenda.tasks[cloned.task]?.container == agenda.inbox)
    }

    @Test func aCloneOfASubtaskStaysUnderItsOpenParent() throws {
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let cloned = try agenda.clone(pack, at: thursdayBefore)
        #expect(agenda.tasks[cloned.task]?.parent == move)
    }

    @Test func anyTaskCanBeDeleted() throws { // T9, T10, T11
        var agenda = Agenda()
        let archived = try agenda.addTask("Old", at: thursdayBefore)
        try agenda.complete(archived, at: thursdayBefore)
        try agenda.delete(archived)
        #expect(agenda.tasks[archived] == nil)

        let weekly = try agenda.addTask(
            "Bins out", plan: Plan(start: moment(2026, 11, 2), recurrence: Recurrence(.weekly)), at: thursdayBefore
        )
        try agenda.complete(weekly, at: at(2026, 11, 2))
        try agenda.delete(weekly)
        #expect(agenda.completions.isEmpty)

        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let photo = try agenda.addBlob(.photo, to: pack)
        let deleted = try agenda.delete(move)
        #expect(deleted.tasks == [move, pack])
        #expect(deleted.blobs == [photo])
        #expect(agenda.tasks.isEmpty)
    }

    @Test func deletingCloseTheGapInASequence() throws { // T11
        var agenda = Agenda()
        let a = try agenda.addTask("A", at: thursdayBefore)
        let b = try agenda.addTask("B", at: thursdayBefore)
        let c = try agenda.addTask("C", at: thursdayBefore)
        try agenda.link(a, then: b)
        try agenda.link(b, then: c)

        try agenda.delete(b)
        #expect(agenda.tasks[c]?.previous == a)
        try agenda.delete(a)
        #expect(agenda.tasks[c]?.previous == nil)
        #expect(!agenda.isLocked(c))
    }

    @Test func finishingAProjectArchivesWhatIsLeftAsNotDone() throws { // C2, C3, T8
        var agenda = Agenda()
        let wedding = agenda.addProject("Wedding")
        let venue = try agenda.addTask("Book venue", in: wedding, at: thursdayBefore)
        let music = try agenda.addTask("Pick music", in: wedding, at: thursdayBefore)
        try agenda.complete(venue, at: thursdayBefore)

        try agenda.completeProject(wedding, at: thursdayBefore)
        #expect(agenda.containers[wedding]?.archived?.outcome == .done)
        #expect(agenda.tasks[venue]?.archived?.outcome == .done)
        #expect(agenda.tasks[music]?.archived?.outcome == .notDone)
        #expect(throws: RuleViolation.archived) { try agenda.addTask("Thank-you cards", in: wedding, at: thursdayBefore) }
    }

    @Test func finishingAProjectCanMarkEverythingDone() throws { // C6
        var agenda = Agenda()
        let wedding = agenda.addProject("Wedding")
        let music = try agenda.addTask("Pick music", in: wedding, at: thursdayBefore)
        try agenda.completeProject(wedding, openTasks: .markDone, at: thursdayBefore)
        #expect(agenda.tasks[music]?.archived?.outcome == .done)
    }

    @Test func markAllDoneAfterFinishingAParent() throws { // S10
        var agenda = Agenda()
        let move = try agenda.addTask("Move flat", at: thursdayBefore)
        let pack = try agenda.addSubtask("Pack", to: move, at: thursdayBefore)
        let earlier = try agenda.addSubtask("Cancel internet", to: move, at: thursdayBefore)
        try agenda.complete(earlier, at: at(2026, 10, 28))
        try agenda.complete(move, at: thursdayBefore)

        try agenda.markSubtasksDone(of: move)
        #expect(agenda.tasks[pack]?.archived?.outcome == .done)
        #expect(agenda.tasks[earlier]?.archived?.at == at(2026, 10, 28).now)
    }

    @Test func markAllDoneAfterFinishingAProject() throws { // C6
        var agenda = Agenda()
        let wedding = agenda.addProject("Wedding")
        let music = try agenda.addTask("Pick music", in: wedding, at: thursdayBefore)
        try agenda.completeProject(wedding, at: thursdayBefore)
        try agenda.markLeftoversDone(inProject: wedding)
        #expect(agenda.tasks[music]?.archived?.outcome == .done)
    }

    @Test func theInboxIsTheSameOnEveryDevice() {
        #expect(Agenda().inbox == Agenda().inbox)
    }

    @Test func listsNeverFinish() throws { // C1
        var agenda = Agenda()
        let groceries = agenda.addList("Groceries")
        #expect(throws: RuleViolation.notAProject) { try agenda.completeProject(groceries, at: thursdayBefore) }
        #expect(throws: RuleViolation.notAProject) { try agenda.completeProject(agenda.inbox, at: thursdayBefore) }
    }

    @Test func newTasksLandInTheInbox() throws { // C4, C5
        var agenda = Agenda()
        let inbox = try #require(agenda.containers[agenda.inbox])
        #expect(inbox.kind == .list)
        #expect(inbox.isInbox)

        let task = try agenda.addTask("Something", at: thursdayBefore)
        #expect(agenda.tasks[task]?.container == agenda.inbox)
    }

    @Test func notesCanStandAlone() throws { // N1, N2
        var agenda = Agenda()
        let home = agenda.addList("Home")
        let wedding = agenda.addProject("Wedding")
        try agenda.addNote("Wifi password is on the router", to: .container(home), at: thursdayBefore)
        try agenda.addNote("Budget: 15k", to: .container(wedding), at: thursdayBefore)
        let venue = try agenda.addTask("Book venue", in: wedding, at: thursdayBefore)
        try agenda.addNote("Ask about parking", to: .task(venue), at: thursdayBefore)
        try agenda.addNote("And catering", to: .task(venue), at: thursdayBefore)

        #expect(agenda.containers[home]?.notes.count == 1)
        #expect(agenda.containers[wedding]?.notes.count == 1)
        #expect(agenda.tasks[venue]?.notes.count == 2)
    }

    @Test func aBlobCanBeTheTask() throws { // B1, B2
        var agenda = Agenda()
        let letter = try agenda.addTask(capturing: .scan, title: "Letter from the council", at: thursdayBefore)
        let task = try #require(agenda.tasks[letter])
        #expect(task.blobs.map(\.kind) == [.scan])
        #expect(task.primaryBlob == task.blobs.first?.id)

        for kind in [BlobRef.Kind.photo, .file, .voice, .link] {
            try agenda.addBlob(kind, to: letter)
        }
        #expect(agenda.tasks[letter]?.blobs.count == 5)
    }
}
