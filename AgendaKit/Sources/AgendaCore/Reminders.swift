import Foundation

/// When one reminder fires.
public struct ReminderTime: Hashable, Sendable {
    /// The same for the same task, reminder and occurrence, so the reminder engine can tell what
    /// iOS already has scheduled (ARCHITECTURE §3.3).
    public var key: String
    public var task: TaskID
    public var reminder: ReminderID
    public var kind: Reminder.Kind
    public var isMain: Bool
    public var date: Date
}

extension Agenda {
    /// Adds a reminder that counts from the do date if it's the task's first, which makes it the
    /// main reminder (R1, R4), or from the main reminder otherwise (R3).
    @discardableResult
    public mutating func addReminder(_ kind: Reminder.Kind, _ offset: ReminderOffset, to id: TaskID) throws(RuleViolation) -> ReminderID {
        _ = try activeTask(id)
        let reminder = Reminder(kind: kind, offset: offset)
        if tasks[id]!.mainReminder == nil {
            tasks[id]!.mainReminder = reminder
        } else {
            tasks[id]!.reminders.append(reminder)
        }
        return reminder.id
    }

    /// Adds a reminder at a given day and time, such as "Thursday 9:00". On a task with no dates,
    /// that time becomes the task's start (R8).
    @discardableResult
    public mutating func addReminder(
        _ kind: Reminder.Kind,
        on moment: Moment,
        to id: TaskID,
        at context: Context
    ) throws(RuleViolation) -> ReminderID {
        let task = try activeTask(id)
        let time = moment.time ?? Reminder.defaultTime
        if try schedule(of: id, at: context).doDate == nil {
            var plan = task.plan
            plan.start = Moment(moment.day, time)
            try setPlan(id, to: plan)
        }
        let anchor: Day
        if let main = task.mainReminder, let doDate = try schedule(of: id, at: context).doDate {
            anchor = Day(Self.resolve(main.offset, from: doDate, in: context.calendar), in: context.calendar)
        } else {
            anchor = try schedule(of: id, at: context).doDate!.day
        }
        return try addReminder(kind, .on(days: anchor.days(to: moment.day), at: time), to: id)
    }

    /// Removes a reminder. When the main one goes, the earliest remaining reminder becomes the main
    /// one, and every remaining reminder keeps its time (R9).
    public mutating func removeReminder(_ reminderID: ReminderID, from id: TaskID, at context: Context) throws(RuleViolation) {
        let task = try activeTask(id)
        if let index = task.reminders.firstIndex(where: { $0.id == reminderID }) {
            tasks[id]!.reminders.remove(at: index)
            return
        }
        guard let main = task.mainReminder, main.id == reminderID else { throw .notFound }
        tasks[id]!.mainReminder = nil
        guard !task.reminders.isEmpty else { return }
        guard let doDate = try schedule(of: id, at: context).doDate else {
            tasks[id]!.mainReminder = task.reminders[0]
            tasks[id]!.reminders.removeFirst()
            return
        }
        let calendar = context.calendar
        let mainMoment = Moment(Self.resolve(main.offset, from: doDate, in: calendar), in: calendar)
        let remaining = task.reminders
            .map { (reminder: $0, moment: Moment(Self.resolve($0.offset, from: mainMoment, in: calendar), in: calendar)) }
            .sorted { $0.moment.start(in: calendar) < $1.moment.start(in: calendar) }
        let newMain = remaining[0]
        tasks[id]!.mainReminder = Reminder(
            id: newMain.reminder.id,
            kind: newMain.reminder.kind,
            offset: .on(days: doDate.day.days(to: newMain.moment.day), at: newMain.moment.time!)
        )
        tasks[id]!.reminders = remaining.dropFirst().map { reminder, moment in
            Reminder(
                id: reminder.id,
                kind: reminder.kind,
                offset: .on(days: newMain.moment.day.days(to: moment.day), at: moment.time!)
            )
        }
    }

    /// When each of the task's reminders fires for its current occurrence. They follow any
    /// reschedule (D2). Archived and locked tasks have none (S9).
    public func reminderTimes(for id: TaskID, at context: Context) -> [ReminderTime] {
        guard let task = tasks[id], !task.isArchived, !isLocked(id), let main = task.mainReminder,
              let doDate = try? schedule(of: id, at: context).doDate else { return [] }
        let calendar = context.calendar
        let occurrence = task.plan.recurrence == nil ? "once" : occurrenceDay(task)!.description
        func time(_ reminder: Reminder, _ date: Date, isMain: Bool) -> ReminderTime {
            ReminderTime(
                key: "\(id.uuidString)/\(reminder.id.uuidString)/\(occurrence)",
                task: id, reminder: reminder.id, kind: reminder.kind, isMain: isMain, date: date
            )
        }
        let mainDate = Self.resolve(main.offset, from: doDate, in: calendar)
        let mainMoment = Moment(mainDate, in: calendar)
        return [time(main, mainDate, isMain: true)]
            + task.reminders.map { time($0, Self.resolve($0.offset, from: mainMoment, in: calendar), isMain: false) }
    }

    /// The instant `offset` points to, counting from `anchor`. A whole-day anchor counts from 09:00 (R10).
    static func resolve(_ offset: ReminderOffset, from anchor: Moment, in calendar: Calendar) -> Date {
        let timed = Moment(anchor.day, anchor.time ?? Reminder.defaultTime)
        switch offset {
        case .days(let days):
            return timed.adding(days: days).start(in: calendar)
        case .minutes(let minutes):
            return timed.start(in: calendar).addingTimeInterval(TimeInterval(minutes * 60))
        case .on(let days, let time):
            return Moment(anchor.day.adding(days: days), time).start(in: calendar)
        }
    }
}
