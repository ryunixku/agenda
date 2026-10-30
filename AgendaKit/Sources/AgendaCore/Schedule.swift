import Foundation

/// Where a task stands right now. Worked out from the plan and any reschedule, never stored
/// (ARCHITECTURE §3.2), so the app, the calendar and the reminders can't disagree.
public struct Schedule: Hashable, Sendable {
    /// When the task is to be done now.
    public var doDate: Moment?
    public var start: Moment?
    public var deadline: Moment?
    /// The plan's dates for the current occurrence, for showing "planned Monday".
    public var plannedStart: Moment?
    public var plannedDeadline: Moment?
    public var isRescheduled: Bool
    /// The do date's day is over and the task isn't done.
    public var isOverdue: Bool
    public var isPastDeadline: Bool
}

/// One-tap reschedule choices (D6).
public enum ReschedulePreset: Hashable, Sendable, CaseIterable {
    /// Today at 19:00.
    case tonight
    /// Tomorrow, at the task's current time if it has one.
    case tomorrow
    /// A week from today, at the task's current time if it has one.
    case nextWeek
}

extension Agenda {
    public func schedule(of id: TaskID, at context: Context) throws(RuleViolation) -> Schedule {
        let task = try storedTask(id)
        let planned = plannedDates(task)
        var schedule = Schedule(
            doDate: planned.start ?? planned.deadline,
            start: planned.start,
            deadline: planned.deadline,
            plannedStart: planned.start,
            plannedDeadline: planned.deadline,
            isRescheduled: false,
            isOverdue: false,
            isPastDeadline: false
        )
        // A one-off task stays where it was moved. A recurring one goes back to its schedule once
        // the day it was moved to is over (D3, D5).
        if let moved = task.rescheduled, task.plan.recurrence == nil || context.today <= moved.doDate.day {
            schedule.doDate = moved.doDate
            schedule.start = moved.doDate
            schedule.deadline = moved.deadline ?? planned.deadline
            schedule.isRescheduled = true
        }
        if !task.isArchived {
            schedule.isOverdue = schedule.doDate.map { context.today > $0.day } ?? false
            schedule.isPastDeadline = schedule.deadline.map { context.now >= $0.end(in: context.calendar) } ?? false
        }
        return schedule
    }

    /// Moves when the task is to be done, leaving its plan alone (D1). Every reminder follows (D2).
    /// Pass `deadline` to move the deadline in the same step, for when the new date is past it (D4).
    public mutating func reschedule(_ id: TaskID, to doDate: Moment, deadline: Moment? = nil) throws(RuleViolation) {
        _ = try activeTask(id)
        if let deadline, doDate.isLater(than: deadline) { throw .deadlineBeforeStart }
        tasks[id]!.rescheduled = Reschedule(doDate: doDate, deadline: deadline)
    }

    /// A one-tap reschedule. Presets never move the deadline (D7).
    public mutating func reschedule(_ id: TaskID, to preset: ReschedulePreset, at context: Context) throws(RuleViolation) {
        try reschedule(id, to: moment(for: preset, task: id, at: context))
    }

    public func moment(for preset: ReschedulePreset, task id: TaskID, at context: Context) throws(RuleViolation) -> Moment {
        let time = try schedule(of: id, at: context).doDate?.time
        switch preset {
        case .tonight: return Moment(context.today, TimeOfDay(19, 0))
        case .tomorrow: return Moment(context.today.adding(days: 1), time)
        case .nextWeek: return Moment(context.today.adding(days: 7), time)
        }
    }

    /// What can be done now, for the Now screen and "What's next": open, not locked, and due to be
    /// done today or earlier (S9). Earliest first.
    public func actionable(at context: Context) -> [TaskItem] {
        tasks.values
            .compactMap { task -> (task: TaskItem, doDate: Moment)? in
                guard !task.isArchived, !isLocked(task.id),
                      let doDate = try? schedule(of: task.id, at: context).doDate,
                      doDate.day <= context.today else { return nil }
                return (task, doDate)
            }
            .sorted { lhs, rhs in
                if lhs.doDate != rhs.doDate { return Moment.isEarlier(lhs.doDate, rhs.doDate) }
                return (lhs.task.createdAt, lhs.task.id.uuidString) < (rhs.task.createdAt, rhs.task.id.uuidString)
            }
            .map(\.task)
    }

    /// The planned day of a recurring task's current occurrence, or of a one-off task.
    func occurrenceDay(_ task: TaskItem) -> Day? {
        task.occurrence ?? task.plan.doDate?.day
    }

    /// The plan's dates, moved to the current occurrence for a recurring task. Each occurrence
    /// keeps the same gap between start and deadline.
    private func plannedDates(_ task: TaskItem) -> (start: Moment?, deadline: Moment?) {
        guard task.plan.recurrence != nil, let first = task.plan.doDate?.day, let current = task.occurrence else {
            return (task.plan.start, task.plan.deadline)
        }
        let shift = first.days(to: current)
        return (task.plan.start?.adding(days: shift), task.plan.deadline?.adding(days: shift))
    }
}
