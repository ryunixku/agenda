import AgendaCore
import CoreData
import Foundation
import Observation
import SwiftData

/// The one place data is read and written. The app, widgets, intents, notification buttons and
/// the share extension all change data through `perform`, which runs a rule from `AgendaCore` and
/// saves what it changed (ARCHITECTURE §3.1).
@MainActor
@Observable
public final class AgendaStore {
    /// Everything, as the core sees it. Views read from here.
    public private(set) var agenda: Agenda

    /// Runs after every change, for the reminder engine and widget reloads.
    @ObservationIgnored public var didChange: (@MainActor (Agenda) -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var taskRecords: [UUID: TaskRecord] = [:]
    @ObservationIgnored private var containerRecords: [UUID: ContainerRecord] = [:]
    @ObservationIgnored private var completionRecords: [UUID: CompletionRecord] = [:]
    @ObservationIgnored private let encoder = JSONEncoder()
    @ObservationIgnored private let decoder = JSONDecoder()

    public init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
        agenda = Agenda()
        reload()
    }

    /// A store that syncs through the user's private iCloud database, kept in the App Group so the
    /// app and its extensions share it. Falls back to this device only if iCloud can't be set up.
    public static func makeContainer(appGroup: String?, cloudKitContainer: String?) throws -> ModelContainer {
        let schema = Schema([TaskRecord.self, ContainerRecord.self, CompletionRecord.self, BlobRecord.self])
        let group: ModelConfiguration.GroupContainer = appGroup.map { .identifier($0) } ?? .none
        if let cloudKitContainer, let container = try? ModelContainer(
            for: schema,
            configurations: ModelConfiguration("Agenda", schema: schema, groupContainer: group, cloudKitDatabase: .private(cloudKitContainer))
        ) {
            return container
        }
        return try ModelContainer(
            for: schema,
            configurations: ModelConfiguration("Agenda", schema: schema, groupContainer: group, cloudKitDatabase: .none)
        )
    }

    /// A store that lives in memory, for tests and previews.
    public static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([TaskRecord.self, ContainerRecord.self, CompletionRecord.self, BlobRecord.self])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    // MARK: Changing data

    /// Runs a rule on the agenda and saves the result. If the rule throws, nothing changes.
    @discardableResult
    public func perform<Result>(_ change: (inout Agenda) throws(RuleViolation) -> Result) throws(RuleViolation) -> Result {
        var updated = agenda
        let result = try change(&updated)
        save(from: agenda, to: updated)
        return result
    }

    /// Captures content as a task of its own (B2), titled from the content unless `title` is given.
    @discardableResult
    public func capture(
        _ content: CapturedContent,
        title: String? = nil,
        in container: ContainerID? = nil,
        at context: Context = Context()
    ) throws(RuleViolation) -> TaskID {
        let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? content.suggestedTitle
        let id = try perform { agenda throws(RuleViolation) in
            try agenda.addTask(capturing: content.kind, title: name, in: container, at: context)
        }
        if let blob = agenda.tasks[id]?.primaryBlob {
            insertBlob(blob, content)
        }
        return id
    }

    /// Adds captured content to an existing task (B2: a task can have any number of blobs).
    @discardableResult
    public func attach(_ content: CapturedContent, to task: TaskID) throws(RuleViolation) -> BlobID {
        let blob = try perform { agenda throws(RuleViolation) in try agenda.addBlob(content.kind, to: task) }
        insertBlob(blob, content)
        return blob
    }

    public func removeBlob(_ blob: BlobID, from task: TaskID) throws(RuleViolation) {
        try perform { agenda throws(RuleViolation) in try agenda.removeBlob(blob, from: task) }
        deleteBlobs([blob])
    }

    /// Clones a task and copies its blobs' bytes, so the clone is independent (T3).
    @discardableResult
    public func clone(_ task: TaskID, at context: Context = Context()) throws(RuleViolation) -> TaskID {
        let cloned = try perform { agenda throws(RuleViolation) in try agenda.clone(task, at: context) }
        for (original, copy) in cloned.blobs {
            if let source = blobRecord(original) {
                self.context.insert(BlobRecord(id: copy, content: content(of: source)))
            }
        }
        commit()
        return cloned.task
    }

    /// Deletes a task for good, with its blobs' bytes (T9).
    public func delete(_ task: TaskID) throws(RuleViolation) {
        let deleted = try perform { agenda throws(RuleViolation) in try agenda.delete(task) }
        deleteBlobs(deleted.blobs)
    }

    // MARK: Reading blobs

    public func content(of blob: BlobID) -> CapturedContent? {
        blobRecord(blob).map(content(of:))
    }

    // MARK: Loading

    /// Reads everything again, for example after iCloud brought changes from another device or an
    /// extension saved something.
    public func reload() {
        let tasks = latest(try? context.fetch(FetchDescriptor<TaskRecord>()), id: \.id, date: \.modifiedAt)
        let containers = latest(try? context.fetch(FetchDescriptor<ContainerRecord>()), id: \.id, date: \.modifiedAt)
        let completions = latest(try? context.fetch(FetchDescriptor<CompletionRecord>()), id: \.id, date: { _ in .distantPast })
        taskRecords = tasks
        containerRecords = containers
        completionRecords = completions

        var loadedContainers = containers.compactMapValues { try? decoder.decode(Container.self, from: $0.payload) }
        let empty = Agenda()
        if loadedContainers[empty.inbox] == nil {
            loadedContainers[empty.inbox] = empty.containers[empty.inbox]
        }
        agenda = Agenda(
            containers: loadedContainers,
            tasks: tasks.compactMapValues { try? decoder.decode(TaskItem.self, from: $0.payload) },
            completions: completions.values.compactMap { try? decoder.decode(Completion.self, from: $0.payload) },
            inbox: empty.inbox
        )
    }

    // MARK: Saving

    private func save(from old: Agenda, to new: Agenda) {
        for (id, task) in new.tasks where old.tasks[id] != task || taskRecords[id] == nil {
            upsert(task, id: id, in: &taskRecords, make: TaskRecord.init)
        }
        for id in old.tasks.keys where new.tasks[id] == nil {
            remove(id, from: &taskRecords)
        }
        for (id, container) in new.containers where old.containers[id] != container || containerRecords[id] == nil {
            upsert(container, id: id, in: &containerRecords, make: ContainerRecord.init)
        }
        for id in old.containers.keys where new.containers[id] == nil {
            remove(id, from: &containerRecords)
        }
        let newCompletions = Dictionary(new.completions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (id, completion) in newCompletions where completionRecords[id] == nil {
            let record = CompletionRecord(id: id, payload: (try? encoder.encode(completion)) ?? Data())
            context.insert(record)
            completionRecords[id] = record
        }
        for id in completionRecords.keys where newCompletions[id] == nil {
            remove(id, from: &completionRecords)
        }
        agenda = new
        commit()
    }

    private func commit() {
        try? context.save()
        didChange?(agenda)
    }

    private func upsert<Value: Encodable, Record: PersistentModel>(
        _ value: Value,
        id: UUID,
        in records: inout [UUID: Record],
        make: (UUID, Data) -> Record
    ) {
        let payload = (try? encoder.encode(value)) ?? Data()
        if let record = records[id] {
            if let task = record as? TaskRecord {
                task.payload = payload
                task.modifiedAt = .now
            } else if let container = record as? ContainerRecord {
                container.payload = payload
                container.modifiedAt = .now
            }
        } else {
            let record = make(id, payload)
            context.insert(record)
            records[id] = record
        }
    }

    private func remove<Record: PersistentModel>(_ id: UUID, from records: inout [UUID: Record]) {
        if let record = records.removeValue(forKey: id) {
            context.delete(record)
        }
    }

    private func insertBlob(_ id: BlobID, _ content: CapturedContent) {
        context.insert(BlobRecord(id: id, content: content))
        commit()
    }

    private func deleteBlobs(_ ids: Set<BlobID>) {
        for id in ids {
            let descriptor = FetchDescriptor<BlobRecord>(predicate: #Predicate { $0.id == id })
            for record in (try? context.fetch(descriptor)) ?? [] {
                context.delete(record)
            }
        }
        commit()
    }

    private func blobRecord(_ id: BlobID) -> BlobRecord? {
        var descriptor = FetchDescriptor<BlobRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func content(of record: BlobRecord) -> CapturedContent {
        CapturedContent(
            kind: BlobRef.Kind(rawValue: record.kind) ?? .file,
            data: record.data,
            filename: record.filename,
            typeIdentifier: record.typeIdentifier,
            url: record.url.flatMap(URL.init(string:)),
            text: record.text
        )
    }

    /// iCloud can create duplicate records for the same ID. Keeps the newest of each and removes
    /// the rest.
    private func latest<Record: PersistentModel>(_ records: [Record]?, id: (Record) -> UUID, date: (Record) -> Date) -> [UUID: Record] {
        var result: [UUID: Record] = [:]
        for record in records ?? [] {
            let key = id(record)
            if let existing = result[key] {
                if date(record) > date(existing) {
                    context.delete(existing)
                    result[key] = record
                } else {
                    context.delete(record)
                }
            } else {
                result[key] = record
            }
        }
        return result
    }
}
