import Foundation

/// Every list, project and task, and every rule that changes them.
///
/// The app, widgets, notifications, alarms and intents all change data through these methods, so
/// a rule holds the same way wherever the user acts.
public struct Agenda: Hashable, Codable, Sendable {
    public internal(set) var containers: [ContainerID: Container]
    public internal(set) var tasks: [TaskID: TaskItem]
    public internal(set) var completions: [Completion]
    /// The built-in list new tasks land in (C4).
    public let inbox: ContainerID

    /// What happens to tasks still open when their project or parent is finished (C3, S3).
    public enum OpenTasks: Hashable, Sendable {
        case archiveAsNotDone
        case markDone
    }

    public enum NoteOwner: Hashable, Sendable {
        case task(TaskID)
        case container(ContainerID)
    }

    public struct Cloned: Hashable, Sendable {
        public var task: TaskID
        /// Each original blob and its copy, so storage can copy the bytes and the clone stays
        /// independent of the original.
        public var blobs: [BlobID: BlobID]
    }

    public struct Deleted: Hashable, Sendable {
        public var tasks: Set<TaskID>
        /// Blobs whose bytes storage should remove.
        public var blobs: Set<BlobID>
    }

    /// A new, empty agenda with its Inbox.
    public init() {
        let inbox = Container(name: "Inbox", kind: .list, isInbox: true)
        self.init(containers: [inbox.id: inbox], tasks: [:], completions: [], inbox: inbox.id)
    }

    /// An agenda loaded from storage.
    public init(
        containers: [ContainerID: Container],
        tasks: [TaskID: TaskItem],
        completions: [Completion],
        inbox: ContainerID
    ) {
        precondition(containers[inbox]?.isInbox == true, "The Inbox must be one of the containers")
        self.containers = containers
        self.tasks = tasks
        self.completions = completions
        self.inbox = inbox
    }

    // MARK: Lists and projects

    @discardableResult
    public mutating func addList(_ name: String) -> ContainerID {
        add(Container(name: name, kind: .list))
    }

    @discardableResult
    public mutating func addProject(_ name: String) -> ContainerID {
        add(Container(name: name, kind: .project))
    }

    /// Finishes a project and archives it (C2). Tasks still open in it are archived with it, as
    /// not done unless `openTasks` says otherwise (C3), so the history is kept.
    public mutating func completeProject(
        _ id: ContainerID,
        openTasks: OpenTasks = .archiveAsNotDone,
        at context: Context
    ) throws(RuleViolation) {
        let project = try activeContainer(id)
        guard project.kind == .project else { throw .notAProject }
        for task in tasks.values where task.container == id && !task.isArchived {
            archive(task.id, openTasks == .markDone ? .done : .notDone, at: context)
        }
        containers[id]!.archived = Archived(at: context.now, outcome: .done)
    }

    // MARK: Adding tasks

    /// Adds a task to a list or project, or to the Inbox when none is given (C4).
    @discardableResult
    public mutating func addTask(
        _ title: String,
        in container: ContainerID? = nil,
        plan: Plan = Plan(),
        at context: Context
    ) throws(RuleViolation) -> TaskID {
        let containerID = container ?? inbox
        _ = try activeContainer(containerID)
        try validate(plan)
        let task = TaskItem(
            title: title, container: containerID, order: nextOrder(parent: nil, container: containerID),
            plan: plan, createdAt: context.now
        )
        tasks[task.id] = task
        return task.id
    }

    /// Adds a task that *is* a piece of captured content (B2): photograph a letter and the photo is
    /// the task. The task's `primaryBlob` is the new blob.
    @discardableResult
    public mutating func addTask(
        capturing kind: BlobRef.Kind,
        title: String,
        in container: ContainerID? = nil,
        at context: Context
    ) throws(RuleViolation) -> TaskID {
        let id = try addTask(title, in: container, at: context)
        let blob = BlobRef(kind: kind)
        tasks[id]!.blobs.append(blob)
        tasks[id]!.primaryBlob = blob.id
        return id
    }

    @discardableResult
    public mutating func addSubtask(
        _ title: String,
        to parentID: TaskID,
        plan: Plan = Plan(),
        at context: Context
    ) throws(RuleViolation) -> TaskID {
        let parent = try activeTask(parentID)
        if parent.parent != nil { throw .nestingTooDeep }
        if parent.plan.recurrence != nil || plan.recurrence != nil { throw .recurringSubtasks }
        try validate(plan)
        let task = TaskItem(
            title: title, container: parent.container, parent: parentID,
            order: nextOrder(parent: parentID, container: parent.container), plan: plan, createdAt: context.now
        )
        tasks[task.id] = task
        return task.id
    }

    // MARK: Editing tasks

    public mutating func rename(_ id: TaskID, to title: String) throws(RuleViolation) {
        _ = try activeTask(id)
        tasks[id]!.title = title
    }

    /// Changes a task's own schedule (T1). An edit that puts a deadline after the next task's start
    /// is blocked (S5, S6), unless `shiftingNext` is set: then the following tasks move later by as
    /// many whole days as needed.
    public mutating func setPlan(_ id: TaskID, to plan: Plan, shiftingNext: Bool = false) throws(RuleViolation) {
        let task = try activeTask(id)
        try validate(plan)
        if plan.recurrence != nil {
            if task.previous != nil || nextTask(after: id) != nil { throw .recurringInSequence }
            if task.parent != nil || !subtasks(of: id).isEmpty { throw .recurringSubtasks }
        }
        if let previous = task.previous.flatMap({ tasks[$0] }), !previous.isArchived,
           Self.breaksOrder(previous.plan, plan) {
            throw .sequenceDateConflict(previous.id)
        }
        if !shiftingNext, let next = nextTask(after: id), !next.isArchived, Self.breaksOrder(plan, next.plan) {
            throw .sequenceDateConflict(next.id)
        }
        if plan.recurrence != task.plan.recurrence || plan.doDate != task.plan.doDate {
            tasks[id]!.occurrence = nil
        }
        tasks[id]!.plan = plan
        shiftFollowing(id)
    }

    /// Moves a task and its subtasks to another list or project.
    public mutating func move(_ id: TaskID, to containerID: ContainerID) throws(RuleViolation) {
        let task = try activeTask(id)
        if task.parent != nil { throw .subtaskMovesWithParent }
        _ = try activeContainer(containerID)
        tasks[id]!.order = nextOrder(parent: nil, container: containerID)
        tasks[id]!.container = containerID
        for subtask in subtasks(of: id) {
            tasks[subtask.id]!.container = containerID
        }
    }

    // MARK: Sequences

    /// Makes `second` follow `first`. `second` stays locked until `first` is done (S4).
    public mutating func link(_ first: TaskID, then second: TaskID) throws(RuleViolation) {
        let a = try activeTask(first)
        let b = try activeTask(second)
        if a.id == b.id { throw .sequenceCycle }
        if a.plan.recurrence != nil || b.plan.recurrence != nil { throw .recurringInSequence }
        if a.parent != b.parent { throw .sequenceAcrossParents }
        if nextTask(after: first) != nil || b.previous != nil { throw .alreadyLinked }
        var cursor: TaskItem? = b
        while let task = cursor {
            if task.id == first { throw .sequenceCycle }
            cursor = nextTask(after: task.id)
        }
        if Self.breaksOrder(a.plan, b.plan) { throw .sequenceDateConflict(second) }
        tasks[second]!.previous = first
    }

    public mutating func unlink(_ id: TaskID) throws(RuleViolation) {
        _ = try activeTask(id)
        tasks[id]!.previous = nil
    }

    /// Whether a task waits for the one before it (S4). A predecessor that is closed in any way no
    /// longer blocks (S12), and a locked parent locks its subtasks.
    public func isLocked(_ id: TaskID) -> Bool {
        guard let task = tasks[id], !task.isArchived else { return false }
        if let previous = task.previous.flatMap({ tasks[$0] }), !previous.isArchived { return true }
        if let parent = task.parent { return isLocked(parent) }
        return false
    }

    public func nextTask(after id: TaskID) -> TaskItem? {
        tasks.values.first { $0.previous == id }
    }

    public func subtasks(of id: TaskID) -> [TaskItem] {
        tasks.values
            .filter { $0.parent == id }
            .sorted { ($0.order, $0.id.uuidString) < ($1.order, $1.id.uuidString) }
    }

    // MARK: Completing

    /// Marks a task done and archives it (T2).
    ///
    /// - A recurring task archives this occurrence and moves on to the next one still ahead, so
    ///   missed occurrences don't pile up (T5, T7). After the last occurrence the task is archived.
    /// - Open subtasks are archived with their parent, as not done unless `openSubtasks` says
    ///   otherwise (S3).
    /// - Finishing the last open subtask finishes the parent (S2).
    public mutating func complete(
        _ id: TaskID,
        openSubtasks: OpenTasks = .archiveAsNotDone,
        at context: Context
    ) throws(RuleViolation) {
        let task = try activeTask(id)
        if isLocked(id) { throw .locked }
        if let recurrence = task.plan.recurrence, let first = task.plan.doDate?.day {
            let current = task.occurrence ?? first
            completions.append(Completion(task: id, occurrence: current, title: task.title, at: context.now))
            let after = max(current, context.today)
            if let next = recurrence.occurrence(after: after, first: first, firstWeekday: context.calendar.firstWeekday) {
                tasks[id]!.occurrence = next
                tasks[id]!.rescheduled = nil
            } else {
                archive(id, .done, at: context)
            }
            return
        }
        for subtask in subtasks(of: id) where !subtask.isArchived {
            archive(subtask.id, openSubtasks == .markDone ? .done : .notDone, at: context)
        }
        archive(id, .done, at: context)
        if let parentID = task.parent, let parent = tasks[parentID], !parent.isArchived,
           subtasks(of: parentID).allSatisfy({ $0.archived?.outcome == .done }) {
            archive(parentID, .done, at: context)
        }
    }

    // MARK: Clone and delete

    /// Copies any task, active or archived, into a new active task (T3). The copy has the title,
    /// plan, reminders, notes, blobs and subtasks, but no reschedule and no links to other tasks
    /// (T12). A clone of a subtask stays under its parent while the parent is open.
    public mutating func clone(_ id: TaskID, at context: Context) throws(RuleViolation) -> Cloned {
        let source = try storedTask(id)
        var parent: TaskID?
        var container = source.container
        if let parentID = source.parent, let parentTask = tasks[parentID], !parentTask.isArchived {
            parent = parentID
        } else if containers[container]?.archived != nil {
            container = inbox
        }
        var blobs: [BlobID: BlobID] = [:]
        let copy = copyTask(
            source, parent: parent, container: container, order: nextOrder(parent: parent, container: container),
            blobs: &blobs, at: context
        )
        var subtaskCopies: [TaskID: TaskID] = [:]
        for subtask in subtasks(of: id) {
            subtaskCopies[subtask.id] = copyTask(
                subtask, parent: copy, container: container, order: subtask.order, blobs: &blobs, at: context
            )
        }
        // Steps inside the clone keep their order (S8).
        for (original, cloned) in subtaskCopies {
            if let previous = tasks[original]!.previous, let clonedPrevious = subtaskCopies[previous] {
                tasks[cloned]!.previous = clonedPrevious
            }
        }
        return Cloned(task: copy, blobs: blobs)
    }

    /// Deletes a task for good, active or archived, with its subtasks, notes, blobs and archive
    /// history (T9, T10). A sequence closes the gap: A → B → C becomes A → C (T11).
    @discardableResult
    public mutating func delete(_ id: TaskID) throws(RuleViolation) -> Deleted {
        _ = try storedTask(id)
        let removed = Set([id] + subtasks(of: id).map(\.id))
        let blobs = Set(removed.flatMap { tasks[$0]!.blobs.map(\.id) })
        for task in tasks.values where !removed.contains(task.id) {
            var previous = task.previous
            while let previousID = previous, removed.contains(previousID) {
                previous = tasks[previousID]!.previous
            }
            if previous != task.previous {
                tasks[task.id]!.previous = previous
            }
        }
        for taskID in removed {
            tasks[taskID] = nil
        }
        completions.removeAll { removed.contains($0.task) }
        return Deleted(tasks: removed, blobs: blobs)
    }

    // MARK: Notes and blobs

    /// Adds a note to a task (N1), or one that stands alone in a list or project (N2).
    @discardableResult
    public mutating func addNote(_ text: String, to owner: NoteOwner, at context: Context) throws(RuleViolation) -> NoteID {
        let note = Note(text: text, createdAt: context.now)
        switch owner {
        case .task(let id):
            _ = try activeTask(id)
            tasks[id]!.notes.append(note)
        case .container(let id):
            _ = try activeContainer(id)
            containers[id]!.notes.append(note)
        }
        return note.id
    }

    public mutating func removeNote(_ noteID: NoteID, from owner: NoteOwner) throws(RuleViolation) {
        switch owner {
        case .task(let id):
            let task = try activeTask(id)
            guard task.notes.contains(where: { $0.id == noteID }) else { throw .notFound }
            tasks[id]!.notes.removeAll { $0.id == noteID }
        case .container(let id):
            let container = try activeContainer(id)
            guard container.notes.contains(where: { $0.id == noteID }) else { throw .notFound }
            containers[id]!.notes.removeAll { $0.id == noteID }
        }
    }

    @discardableResult
    public mutating func addBlob(_ kind: BlobRef.Kind, to id: TaskID) throws(RuleViolation) -> BlobID {
        _ = try activeTask(id)
        let blob = BlobRef(kind: kind)
        tasks[id]!.blobs.append(blob)
        return blob.id
    }

    public mutating func removeBlob(_ blobID: BlobID, from id: TaskID) throws(RuleViolation) {
        let task = try activeTask(id)
        guard task.blobs.contains(where: { $0.id == blobID }) else { throw .notFound }
        tasks[id]!.blobs.removeAll { $0.id == blobID }
        if task.primaryBlob == blobID {
            tasks[id]!.primaryBlob = nil
        }
    }

    // MARK: Helpers

    func storedTask(_ id: TaskID) throws(RuleViolation) -> TaskItem {
        guard let task = tasks[id] else { throw .notFound }
        return task
    }

    func activeTask(_ id: TaskID) throws(RuleViolation) -> TaskItem {
        let task = try storedTask(id)
        if task.isArchived { throw .archived }
        return task
    }

    func activeContainer(_ id: ContainerID) throws(RuleViolation) -> Container {
        guard let container = containers[id] else { throw .notFound }
        if container.archived != nil { throw .archived }
        return container
    }

    private mutating func add(_ container: Container) -> ContainerID {
        containers[container.id] = container
        return container.id
    }

    /// The position after the last sibling: its parent's subtasks, or the top-level tasks of the container.
    private func nextOrder(parent: TaskID?, container: ContainerID) -> Int {
        let siblings = tasks.values.filter { $0.parent == parent && (parent != nil || $0.container == container) }
        return (siblings.map(\.order).max() ?? -1) + 1
    }

    private mutating func archive(_ id: TaskID, _ outcome: Archived.Outcome, at context: Context) {
        tasks[id]!.archived = Archived(at: context.now, outcome: outcome)
        tasks[id]!.rescheduled = nil
    }

    private func validate(_ plan: Plan) throws(RuleViolation) {
        if let start = plan.start, let deadline = plan.deadline, start.isLater(than: deadline) {
            throw .deadlineBeforeStart
        }
        if let recurrence = plan.recurrence {
            if plan.doDate == nil { throw .recurrenceNeedsDate }
            if !recurrence.isValid { throw .invalidRecurrence }
        }
    }

    /// Whether `first`'s deadline is later than `second`'s start (S5). Only applies when both are set.
    static func breaksOrder(_ first: Plan, _ second: Plan) -> Bool {
        guard let deadline = first.deadline, let start = second.start else { return false }
        return deadline.isLater(than: start)
    }

    /// Moves each following task later by whole days, keeping its length, until the sequence is in
    /// order again (S6).
    private mutating func shiftFollowing(_ id: TaskID) {
        var current = tasks[id]!
        while let next = nextTask(after: current.id), !next.isArchived, Self.breaksOrder(current.plan, next.plan),
              let deadline = current.plan.deadline, let start = next.plan.start {
            var days = start.day.days(to: deadline.day)
            if deadline.isLater(than: start.adding(days: days)) { days += 1 }
            tasks[next.id]!.plan.start = start.adding(days: days)
            tasks[next.id]!.plan.deadline = next.plan.deadline?.adding(days: days)
            current = tasks[next.id]!
        }
    }

    private mutating func copyTask(
        _ source: TaskItem,
        parent: TaskID?,
        container: ContainerID,
        order: Int,
        blobs: inout [BlobID: BlobID],
        at context: Context
    ) -> TaskID {
        func copied(_ reminder: Reminder) -> Reminder {
            Reminder(kind: reminder.kind, offset: reminder.offset)
        }
        var blobCopies: [BlobRef] = []
        for blob in source.blobs {
            let copy = BlobRef(kind: blob.kind)
            blobs[blob.id] = copy.id
            blobCopies.append(copy)
        }
        let copy = TaskItem(
            title: source.title,
            container: container,
            parent: parent,
            order: order,
            plan: source.plan,
            occurrence: source.occurrence,
            mainReminder: source.mainReminder.map(copied),
            reminders: source.reminders.map(copied),
            notes: source.notes.map { Note(text: $0.text, createdAt: context.now) },
            blobs: blobCopies,
            primaryBlob: source.primaryBlob.flatMap { blobs[$0] },
            clonedFrom: source.id,
            createdAt: context.now
        )
        tasks[copy.id] = copy
        return copy.id
    }
}
