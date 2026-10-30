import AgendaCore
import Foundation
import SwiftData
import Testing
@testable import AgendaData

@MainActor
@Suite struct AgendaStoreTests {
    let context = Context(now: Date(timeIntervalSince1970: 1_793_000_000), calendar: Calendar(identifier: .gregorian))

    @Test func changesSurviveReopeningTheStore() throws {
        let container = try AgendaStore.makeInMemoryContainer()
        let store = AgendaStore(container: container)
        let home = try store.perform { $0.addList("Home") }
        let task = try store.perform { agenda throws(RuleViolation) in
            try agenda.addTask("Fix the tap", in: home, plan: Plan(start: Moment(Day(2026, 11, 2))), at: context)
        }
        try store.perform { agenda throws(RuleViolation) in try agenda.addSubtask("Buy washer", to: task, at: context) }
        try store.perform { agenda throws(RuleViolation) in try agenda.addReminder(.alarm, .minutes(-30), to: task) }

        let reopened = AgendaStore(container: container)
        #expect(reopened.agenda == store.agenda)
        #expect(reopened.agenda.tasks[task]?.title == "Fix the tap")
    }

    @Test func aRuleThatFailsChangesNothing() throws {
        let store = AgendaStore(container: try AgendaStore.makeInMemoryContainer())
        let task = try store.perform { agenda throws(RuleViolation) in try agenda.addTask("Done", at: context) }
        try store.perform { agenda throws(RuleViolation) in try agenda.complete(task, at: context) }
        let before = store.agenda

        #expect(throws: RuleViolation.archived) {
            try store.perform { agenda throws(RuleViolation) in try agenda.rename(task, to: "Changed") }
        }
        #expect(store.agenda == before)
    }

    @Test func capturedContentBecomesATask() throws { // B2
        let store = AgendaStore(container: try AgendaStore.makeInMemoryContainer())
        let link = CapturedContent(kind: .link, url: URL(string: "https://www.example.com/article"))
        let task = try store.capture(link, at: context)

        #expect(store.agenda.tasks[task]?.title == "example.com")
        let blob = try #require(store.agenda.tasks[task]?.primaryBlob)
        #expect(store.content(of: blob)?.url == link.url)
    }

    @Test func aCloneHasItsOwnCopyOfTheBlobs() throws { // T3
        let store = AgendaStore(container: try AgendaStore.makeInMemoryContainer())
        let photo = CapturedContent(kind: .photo, data: Data([1, 2, 3]), text: "Receipt")
        let task = try store.capture(photo, at: context)
        let copy = try store.clone(task, at: context)

        let copiedBlob = try #require(store.agenda.tasks[copy]?.primaryBlob)
        #expect(copiedBlob != store.agenda.tasks[task]?.primaryBlob)
        #expect(store.content(of: copiedBlob)?.data == Data([1, 2, 3]))

        try store.delete(task)
        #expect(store.content(of: copiedBlob)?.data == Data([1, 2, 3]))
    }

    @Test func deletingRemovesTheBlobs() throws { // T9
        let store = AgendaStore(container: try AgendaStore.makeInMemoryContainer())
        let task = try store.capture(CapturedContent(kind: .voice, data: Data([9])), at: context)
        let blob = try #require(store.agenda.tasks[task]?.primaryBlob)
        try store.delete(task)
        #expect(store.content(of: blob) == nil)
        #expect(store.agenda.tasks[task] == nil)
    }

    @Test func titlesSuggestedFromContent() {
        #expect(CapturedContent(kind: .scan, text: "Council tax bill\nDue 1 Dec").suggestedTitle == "Council tax bill")
        #expect(CapturedContent(kind: .file, filename: "Lease.pdf").suggestedTitle == "Lease")
        #expect(CapturedContent(kind: .voice).suggestedTitle == "Voice memo")
    }

    @Test func everyChangeIsAnnounced() throws {
        let store = AgendaStore(container: try AgendaStore.makeInMemoryContainer())
        var changes = 0
        store.didChange = { _ in changes += 1 }
        try store.perform { agenda throws(RuleViolation) in try agenda.addTask("One", at: context) }
        #expect(changes == 1)
    }
}
