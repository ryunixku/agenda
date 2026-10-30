import Foundation

/// One task, or one occurrence of a recurring task, as the calendar shows it (K1, K3).
public struct CalendarEntry: Hashable, Sendable, Identifiable {
    public var task: TaskID
    public var title: String
    public var start: Moment?
    public var deadline: Moment?
    /// The plan's do date when the task was rescheduled, to show where it came from (K3).
    public var plannedDoDate: Moment?
    public var isRescheduled: Bool
    /// Recurring tasks only: the planned day of this occurrence.
    public var occurrence: Day?
    public var isRecurring: Bool

    public var id: String {
        "\(task.uuidString)/\(occurrence?.description ?? "once")"
    }

    /// The first and last day the entry covers. A task with a start and a deadline is a span.
    public var firstDay: Day {
        [start?.day, deadline?.day].compactMap { $0 }.min()!
    }

    public var lastDay: Day {
        [start?.day, deadline?.day].compactMap { $0 }.max()!
    }

    public func covers(_ day: Day) -> Bool {
        firstDay <= day && day <= lastDay
    }

    public var isSpan: Bool {
        firstDay != lastDay
    }
}

extension Agenda {
    /// Open tasks with dates that touch the days from `start` through `end`, using the same dates
    /// as the reminders and the Now screen. Recurring tasks show their current occurrence and the
    /// ones after it.
    public func calendar(from start: Day, through end: Day, at context: Context) -> [CalendarEntry] {
        var entries: [CalendarEntry] = []
        for task in tasks.values where !task.isArchived {
            guard let schedule = try? schedule(of: task.id, at: context), schedule.doDate != nil else { continue }
            let current = CalendarEntry(
                task: task.id,
                title: task.title,
                start: schedule.start,
                deadline: schedule.deadline,
                plannedDoDate: schedule.isRescheduled ? (schedule.plannedStart ?? schedule.plannedDeadline) : nil,
                isRescheduled: schedule.isRescheduled,
                occurrence: task.plan.recurrence == nil ? nil : occurrenceDay(task),
                isRecurring: task.plan.recurrence != nil
            )
            entries.append(current)
            guard let recurrence = task.plan.recurrence, let first = task.plan.doDate?.day,
                  let currentDay = occurrenceDay(task) else { continue }
            // Later occurrences may begin before `start` and still reach into the range.
            let length = task.plan.start.flatMap { start in task.plan.deadline.map { start.day.days(to: $0.day) } } ?? 0
            let from = max(currentDay.adding(days: 1), start.adding(days: -max(0, length)))
            for day in recurrence.occurrences(from: from, through: end, first: first, firstWeekday: context.calendar.firstWeekday) {
                let shift = first.days(to: day)
                entries.append(CalendarEntry(
                    task: task.id,
                    title: task.title,
                    start: task.plan.start?.adding(days: shift),
                    deadline: task.plan.deadline?.adding(days: shift),
                    plannedDoDate: nil,
                    isRescheduled: false,
                    occurrence: day,
                    isRecurring: true
                ))
            }
        }
        return entries
            .filter { $0.firstDay <= end && $0.lastDay >= start }
            .sorted { lhs, rhs in
                let left = lhs.start ?? lhs.deadline!
                let right = rhs.start ?? rhs.deadline!
                if left != right { return Moment.isEarlier(left, right) }
                return lhs.title < rhs.title
            }
    }
}
