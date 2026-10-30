import AgendaCore
import AgendaData
import AppIntents
import Foundation

// One set of actions behind every surface (ARCHITECTURE §3.4): widget buttons, Live Activity
// buttons, alarm buttons, Siri, Shortcuts, Spotlight and Control Center all run these.

nonisolated struct TaskEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = TaskQuery()

    let id: UUID
    let title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

nonisolated struct TaskQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        let store = SharedStore.shared
        store.reload()
        return identifiers.compactMap { id in store.agenda.tasks[id].map { TaskEntity(id: id, title: $0.title) } }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TaskEntity] {
        let store = SharedStore.shared
        store.reload()
        return store.agenda.tasks.values
            .filter { !$0.isArchived && $0.title.localizedCaseInsensitiveContains(string) }
            .map { TaskEntity(id: $0.id, title: $0.title) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TaskEntity] {
        let store = SharedStore.shared
        store.reload()
        return store.agenda.actionable(at: Context()).prefix(10).map { TaskEntity(id: $0.id, title: $0.title) }
    }
}

nonisolated enum RescheduleChoice: String, AppEnum {
    case tonight, tomorrow, nextWeek

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "When"
    static let caseDisplayRepresentations: [RescheduleChoice: DisplayRepresentation] = [
        .tonight: "Tonight",
        .tomorrow: "Tomorrow",
        .nextWeek: "Next week",
    ]

    var preset: ReschedulePreset {
        switch self {
        case .tonight: .tonight
        case .tomorrow: .tomorrow
        case .nextWeek: .nextWeek
        }
    }
}

/// The actions every surface shares. Each reloads first, because another process may have
/// changed the data since this one last looked.
@MainActor
enum AgendaActions {
    static func complete(_ id: TaskID) throws(RuleViolation) {
        let store = SharedStore.shared
        store.reload()
        try store.perform { agenda throws(RuleViolation) in try agenda.complete(id, at: Context()) }
    }

    static func reschedule(_ id: TaskID, to preset: ReschedulePreset) throws(RuleViolation) {
        let store = SharedStore.shared
        store.reload()
        try store.perform { agenda throws(RuleViolation) in try agenda.reschedule(id, to: preset, at: Context()) }
    }

    @discardableResult
    static func add(_ title: String) throws(RuleViolation) -> TaskID {
        let store = SharedStore.shared
        store.reload()
        return try store.perform { agenda throws(RuleViolation) in try agenda.addTask(title, at: Context()) }
    }
}

nonisolated struct IntentError: Error, CustomLocalizedStringResourceConvertible {
    let violation: RuleViolation
    var localizedStringResource: LocalizedStringResource {
        "\(violation.message)"
    }
}

struct CompleteTaskIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Task Done"
    static let description = IntentDescription("Marks a task done and archives it.")

    @Parameter(title: "Task") var task: TaskEntity

    init() {}

    init(task: TaskEntity) {
        self.task = task
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        do throws(RuleViolation) {
            try AgendaActions.complete(task.id)
        } catch {
            throw IntentError(violation: error)
        }
        return .result()
    }
}

struct RescheduleTaskIntent: AppIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Reschedule Task"
    static let description = IntentDescription("Moves when a task is to be done. Its plan and deadline stay as they are.")

    @Parameter(title: "Task") var task: TaskEntity
    @Parameter(title: "When", default: .tomorrow) var when: RescheduleChoice

    init() {}

    init(task: TaskEntity, when: RescheduleChoice) {
        self.task = task
        self.when = when
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        do throws(RuleViolation) {
            try AgendaActions.reschedule(task.id, to: when.preset)
        } catch {
            throw IntentError(violation: error)
        }
        return .result()
    }
}

struct AddTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Task"
    static let description = IntentDescription("Adds a task to your Inbox.")

    @Parameter(title: "Title", requestValueDialog: "What do you need to do?") var title: String

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do throws(RuleViolation) {
            try AgendaActions.add(title)
        } catch {
            throw IntentError(violation: error)
        }
        return .result(dialog: "Added “\(title)” to your Inbox.")
    }
}

struct WhatsNextIntent: AppIntent {
    static let title: LocalizedStringResource = "What's Next"
    static let description = IntentDescription("Tells you what to do now.")

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[TaskEntity]> {
        let store = SharedStore.shared
        store.reload()
        let tasks = store.agenda.actionable(at: Context())
        let entities = tasks.map { TaskEntity(id: $0.id, title: $0.title) }
        guard !tasks.isEmpty else {
            return .result(value: entities, dialog: "Nothing to do right now.")
        }
        let names = tasks.prefix(3).map(\.title).formatted(.list(type: .and))
        let more = tasks.count > 3 ? ", and \(tasks.count - 3) more" : ""
        return .result(value: entities, dialog: "Next: \(names)\(more).")
    }
}

/// Opens the app ready to capture: from Control Center, the Action button or Siri.
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture"
    static let description = IntentDescription("Opens Agenda ready to add a task.")
    static let openAppWhenRun = true

    static let requestKey = "capture.requested"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: Bundle.main.infoDictionary?["AgendaAppGroup"] as? String)?.set(true, forKey: Self.requestKey)
        return .result()
    }
}
