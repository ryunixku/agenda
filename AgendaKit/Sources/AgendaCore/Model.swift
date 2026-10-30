import Foundation

public typealias TaskID = UUID
public typealias ContainerID = UUID
public typealias ReminderID = UUID
public typealias NoteID = UUID
public typealias BlobID = UUID

/// A task's own schedule (T1). Only editing the task changes it. Rescheduling never does (D1).
public struct Plan: Hashable, Codable, Sendable {
    public var start: Moment?
    public var deadline: Moment?
    public var recurrence: Recurrence?

    public init(start: Moment? = nil, deadline: Moment? = nil, recurrence: Recurrence? = nil) {
        self.start = start
        self.deadline = deadline
        self.recurrence = recurrence
    }

    /// When the task is meant to be done: its start, or its deadline if it has no start.
    public var doDate: Moment? {
        start ?? deadline
    }
}

/// A move of the do date that leaves the plan alone (D1). For a recurring task it covers the
/// current occurrence only (D5).
public struct Reschedule: Hashable, Codable, Sendable {
    public var doDate: Moment
    /// Set only when the user moved the deadline in the same step (D4, D8).
    public var deadline: Moment?

    public init(doDate: Moment, deadline: Moment? = nil) {
        self.doDate = doDate
        self.deadline = deadline
    }
}

public struct Reminder: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case sticky, alarm
    }

    public let id: ReminderID
    public var kind: Kind
    /// The main reminder counts from the do date (R4). Every other reminder counts from the main
    /// one (R3).
    public var offset: ReminderOffset

    public init(id: ReminderID = UUID(), kind: Kind, offset: ReminderOffset) {
        self.id = id
        self.kind = kind
        self.offset = offset
    }

    /// The time used when a reminder counts from a whole day (R10).
    public static let defaultTime = TimeOfDay(9, 0)
}

public enum ReminderOffset: Hashable, Codable, Sendable {
    /// Whole days from the anchor (negative is before), at the anchor's time. "1 day before".
    /// Counted in calendar days, so the clock time survives a daylight-saving change.
    case days(Int)
    /// Minutes from the anchor (negative is before). "30 minutes before".
    case minutes(Int)
    /// A fixed time, a number of days from the anchor's day. "The day before at 18:00".
    case on(days: Int, at: TimeOfDay)
}

public struct Note: Hashable, Codable, Sendable, Identifiable {
    public let id: NoteID
    public var text: String
    public let createdAt: Date

    public init(id: NoteID = UUID(), text: String, createdAt: Date) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }
}

/// Captured content (B1). The bytes live in storage; the core only tracks which task owns them.
public struct BlobRef: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case photo, scan, file, voice, link
    }

    public let id: BlobID
    public let kind: Kind

    public init(id: BlobID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

/// How something left the active agenda (T8).
public struct Archived: Hashable, Codable, Sendable {
    public enum Outcome: String, Hashable, Codable, Sendable {
        case done
        /// Closed while still open, along with its project or parent (C3, S3).
        case notDone
    }

    public let at: Date
    public let outcome: Outcome

    public init(at: Date, outcome: Outcome) {
        self.at = at
        self.outcome = outcome
    }
}

public struct TaskItem: Hashable, Codable, Sendable, Identifiable {
    public let id: TaskID
    public internal(set) var title: String
    /// The list, project or Inbox the task lives in. Always exactly one (C4).
    public internal(set) var container: ContainerID
    /// Set on a subtask. Subtasks are one level deep (S1).
    public internal(set) var parent: TaskID?
    /// The task this one waits for in a sequence (S4).
    public internal(set) var previous: TaskID?
    /// Position among its siblings: its parent's subtasks, or the top-level tasks of its container.
    public internal(set) var order: Int
    public internal(set) var plan: Plan
    /// Recurring tasks only: the planned day of the current occurrence. Nil means the first one.
    public internal(set) var occurrence: Day?
    public internal(set) var rescheduled: Reschedule?
    /// The base every other reminder counts from (R1).
    public internal(set) var mainReminder: Reminder?
    /// The other reminders, each counting from the main one (R3).
    public internal(set) var reminders: [Reminder]
    public internal(set) var notes: [Note]
    public internal(set) var blobs: [BlobRef]
    /// Set when the task *is* this blob (B2).
    public internal(set) var primaryBlob: BlobID?
    public internal(set) var clonedFrom: TaskID?
    /// Set once the task is archived. Archived tasks are read-only (T2).
    public internal(set) var archived: Archived?
    public let createdAt: Date

    public var isArchived: Bool {
        archived != nil
    }

    /// Rebuilds a task from storage. Change tasks through `Agenda`, so the rules hold.
    public init(
        id: TaskID = UUID(),
        title: String,
        container: ContainerID,
        parent: TaskID? = nil,
        previous: TaskID? = nil,
        order: Int = 0,
        plan: Plan = Plan(),
        occurrence: Day? = nil,
        rescheduled: Reschedule? = nil,
        mainReminder: Reminder? = nil,
        reminders: [Reminder] = [],
        notes: [Note] = [],
        blobs: [BlobRef] = [],
        primaryBlob: BlobID? = nil,
        clonedFrom: TaskID? = nil,
        archived: Archived? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.title = title
        self.container = container
        self.parent = parent
        self.previous = previous
        self.order = order
        self.plan = plan
        self.occurrence = occurrence
        self.rescheduled = rescheduled
        self.mainReminder = mainReminder
        self.reminders = reminders
        self.notes = notes
        self.blobs = blobs
        self.primaryBlob = primaryBlob
        self.clonedFrom = clonedFrom
        self.archived = archived
        self.createdAt = createdAt
    }
}

/// A list, which never ends, or a project, which is meant to be finished (C1).
public struct Container: Hashable, Codable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Codable, Sendable {
        case list, project
    }

    public let id: ContainerID
    public internal(set) var name: String
    public let kind: Kind
    /// The built-in list new tasks land in (C4, C5).
    public let isInbox: Bool
    /// Notes that stand alone in the list or project (N2).
    public internal(set) var notes: [Note]
    /// Projects only, once finished (C2).
    public internal(set) var archived: Archived?

    public init(
        id: ContainerID = UUID(),
        name: String,
        kind: Kind,
        isInbox: Bool = false,
        notes: [Note] = [],
        archived: Archived? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isInbox = isInbox
        self.notes = notes
        self.archived = archived
    }
}

/// The archive entry for one finished occurrence of a recurring task (T5).
public struct Completion: Hashable, Codable, Sendable, Identifiable {
    public let id: UUID
    public let task: TaskID
    /// The planned day of the occurrence that was done.
    public let occurrence: Day
    /// The title at the time, since the task itself carries on and may be renamed.
    public let title: String
    public let at: Date

    public init(id: UUID = UUID(), task: TaskID, occurrence: Day, title: String, at: Date) {
        self.id = id
        self.task = task
        self.occurrence = occurrence
        self.title = title
        self.at = at
    }
}

public enum RuleViolation: Error, Hashable, Sendable {
    case notFound
    /// Archived tasks and projects are read-only (T2).
    case archived
    /// The task waits for the one before it in a sequence (S4, S12).
    case locked
    /// A subtask can't have subtasks (S1).
    case nestingTooDeep
    /// Recurring tasks can't have subtasks or be subtasks (S14).
    case recurringSubtasks
    /// Recurring tasks can't be in a sequence (S7).
    case recurringInSequence
    /// A sequence links top-level tasks, or subtasks of the same parent (S8, S13).
    case sequenceAcrossParents
    /// A task has at most one previous and one next task (S13).
    case alreadyLinked
    case sequenceCycle
    /// A deadline would be later than the next task's start (S5). Carries the other task.
    case sequenceDateConflict(TaskID)
    case deadlineBeforeStart
    case recurrenceNeedsDate
    case invalidRecurrence
    /// Only projects can be finished. Lists never end (C1).
    case notAProject
    /// A subtask always lives with its parent.
    case subtaskMovesWithParent
}
