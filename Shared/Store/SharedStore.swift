import AgendaCore
import AgendaData
import Foundation
import SwiftData

/// The store the app and its extensions share: the same App Group file, synced through the same
/// iCloud container. Each target says what happens after a change in `afterChange`.
enum SharedStore {
    static let shared: AgendaStore = {
        let store = AgendaStore(container: makeContainer())
        store.didChange = { agenda in afterChange(agenda) }
        return store
    }()

    private static func makeContainer() -> ModelContainer {
        let info = Bundle.main.infoDictionary ?? [:]
        let group = info["AgendaAppGroup"] as? String
        let cloud = info["AgendaCloudKitContainer"] as? String
        if let container = try? AgendaStore.makeContainer(appGroup: group, cloudKitContainer: cloud) {
            return container
        }
        if let container = try? AgendaStore.makeContainer(appGroup: nil, cloudKitContainer: nil) {
            return container
        }
        return try! AgendaStore.makeInMemoryContainer()
    }
}

/// Plain words for each rule, for when the app has to say no.
extension RuleViolation {
    var message: String {
        switch self {
        case .notFound: "That item no longer exists."
        case .archived: "This is archived, so it can't be changed. You can clone it instead."
        case .locked: "This task waits for the one before it."
        case .nestingTooDeep: "Subtasks can't have subtasks of their own."
        case .recurringSubtasks: "Repeating tasks can't have subtasks or be subtasks."
        case .recurringInSequence: "Repeating tasks can't be part of a sequence."
        case .sequenceAcrossParents: "Only tasks at the same level can follow each other."
        case .alreadyLinked: "That task is already in a sequence."
        case .sequenceCycle: "That would make a loop."
        case .sequenceDateConflict: "A deadline can't be later than the start of the task that follows it."
        case .deadlineBeforeStart: "The deadline can't be before the start."
        case .recurrenceNeedsDate: "A repeating task needs a date."
        case .invalidRecurrence: "That repeat isn't valid."
        case .notAProject: "Only projects can be finished. Lists never end."
        case .subtaskMovesWithParent: "Subtasks move with their parent."
        }
    }
}
