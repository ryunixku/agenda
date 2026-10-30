import AgendaCore
import Foundation

/// Short, plain wording for dates and reminders.
enum Format {
    /// "Today", "Tomorrow", "Yesterday", "Wed", or "3 Nov", plus the time if there is one.
    static func moment(_ moment: Moment, today: Day = Context().today) -> String {
        let day = day(moment.day, today: today)
        guard let time = moment.time else { return day }
        return "\(day) \(self.time(time))"
    }

    static func day(_ day: Day, today: Day = Context().today) -> String {
        let date = Moment(day).start(in: .current)
        switch today.days(to: day) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case -6...6: return date.formatted(.dateTime.weekday(.abbreviated))
        default:
            if day.year == today.year { return date.formatted(.dateTime.day().month(.abbreviated)) }
            return date.formatted(.dateTime.day().month(.abbreviated).year())
        }
    }

    static func time(_ time: TimeOfDay) -> String {
        Moment(Day(2000, 1, 1), time).start(in: .current).formatted(date: .omitted, time: .shortened)
    }

    static func long(_ day: Day) -> String {
        Moment(day).start(in: .current).formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func reminder(_ offset: ReminderOffset, isMain: Bool) -> String {
        let anchor = isMain ? "the task" : "the main reminder"
        switch offset {
        case .minutes(0):
            return isMain ? "At the time of the task" : "With the main reminder"
        case .minutes(let minutes):
            return "\(duration(abs(minutes))) \(minutes < 0 ? "before" : "after") \(anchor)"
        case .days(let days):
            return "\(abs(days)) \(abs(days) == 1 ? "day" : "days") \(days < 0 ? "before" : "after") \(anchor)"
        case .on(let days, let at):
            let time = time(at)
            switch days {
            case 0: return isMain ? "On the day at \(time)" : "Same day as the main reminder, at \(time)"
            case -1: return "The day before at \(time)"
            case 1: return "The day after at \(time)"
            default: return "\(abs(days)) days \(days < 0 ? "before" : "after") at \(time)"
            }
        }
    }

    static func duration(_ minutes: Int) -> String {
        if minutes % (60 * 24) == 0 { return "\(minutes / (60 * 24)) \(minutes == 60 * 24 ? "day" : "days")" }
        if minutes % 60 == 0 { return "\(minutes / 60) \(minutes == 60 ? "hour" : "hours")" }
        return "\(minutes) min"
    }

    static func recurrence(_ recurrence: Recurrence) -> String {
        let unit: String
        switch recurrence.frequency {
        case .daily: unit = recurrence.interval == 1 ? "day" : "days"
        case .weekly: unit = recurrence.interval == 1 ? "week" : "weeks"
        case .monthly: unit = recurrence.interval == 1 ? "month" : "months"
        case .yearly: unit = recurrence.interval == 1 ? "year" : "years"
        }
        let every = recurrence.interval == 1 ? "Every \(unit)" : "Every \(recurrence.interval) \(unit)"
        if recurrence.frequency == .weekly, !recurrence.weekdays.isEmpty {
            let symbols = Calendar.current.shortWeekdaySymbols
            let names = recurrence.weekdays.sorted { weekdayOrder($0) < weekdayOrder($1) }.map { symbols[$0 - 1] }
            return "\(every) on \(names.formatted(.list(type: .and)))"
        }
        return every
    }

    /// Sorts weekdays from the user's first day of the week.
    static func weekdayOrder(_ weekday: Int) -> Int {
        (weekday - Calendar.current.firstWeekday + 7) % 7
    }
}

extension Moment {
    /// The moment as a `Date` in the user's calendar, for date pickers.
    var date: Date {
        start(in: .current)
    }

    init(date: Date, includingTime: Bool) {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(Day(date, in: calendar), includingTime ? TimeOfDay(parts.hour!, parts.minute!) : nil)
    }
}
