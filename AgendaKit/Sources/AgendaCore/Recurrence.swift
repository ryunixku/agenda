/// A fixed repeat schedule, such as every Monday or the 1st of each month (T6).
///
/// Every occurrence is counted from the series' first day, so "the 31st of every month" comes
/// back to the 31st after February instead of drifting to the 28th.
public struct Recurrence: Hashable, Codable, Sendable {
    public enum Frequency: String, Hashable, Codable, Sendable {
        case daily, weekly, monthly, yearly
    }

    public var frequency: Frequency
    /// Every `interval` days, weeks, months or years.
    public var interval: Int
    /// Weekly only. 1 is Sunday and 7 is Saturday. Empty means the weekday of the first occurrence.
    public var weekdays: Set<Int>
    /// No occurrence falls after this day.
    public var until: Day?

    public init(_ frequency: Frequency, every interval: Int = 1, on weekdays: Set<Int> = [], until: Day? = nil) {
        self.frequency = frequency
        self.interval = interval
        self.weekdays = weekdays
        self.until = until
    }

    var isValid: Bool {
        interval >= 1 && weekdays.allSatisfy { (1...7).contains($0) }
    }

    /// The first occurrence after `day` in a series that starts on `first`, or nil once the series
    /// has ended. `first` always counts as an occurrence. `firstWeekday` decides where a week starts
    /// when repeating every few weeks.
    public func occurrence(after day: Day, first: Day, firstWeekday: Int) -> Day? {
        let next = day < first ? first : candidate(after: day, first: first, firstWeekday: firstWeekday)
        if let until, next > until { return nil }
        return next
    }

    /// Every occurrence from `start` through `end`, inclusive.
    public func occurrences(from start: Day, through end: Day, first: Day, firstWeekday: Int) -> [Day] {
        var result: [Day] = []
        var next = occurrence(after: start.adding(days: -1), first: first, firstWeekday: firstWeekday)
        while let day = next, day <= end {
            result.append(day)
            next = occurrence(after: day, first: first, firstWeekday: firstWeekday)
        }
        return result
    }

    // `day` is on or after `first`.
    private func candidate(after day: Day, first: Day, firstWeekday: Int) -> Day {
        let interval = max(1, interval)
        switch frequency {
        case .daily:
            let steps = first.days(to: day) / interval + 1
            return first.adding(days: steps * interval)
        case .weekly:
            let repeatDays = weekdays.isEmpty ? [first.weekday] : weekdays
            let firstWeekStart = first.adding(days: -((first.weekday - firstWeekday + 7) % 7))
            var candidate = day.adding(days: 1)
            while true {
                let week = firstWeekStart.days(to: candidate) / 7
                if week % interval == 0, repeatDays.contains(candidate.weekday) { return candidate }
                candidate = candidate.adding(days: 1)
            }
        case .monthly, .yearly:
            let monthsPerStep = frequency == .monthly ? interval : interval * 12
            let monthsSoFar = (day.year - first.year) * 12 + (day.month - first.month)
            var step = max(0, monthsSoFar / monthsPerStep)
            while true {
                let candidate = Self.day(first.day, monthsAfter: step * monthsPerStep, from: first)
                if candidate > day { return candidate }
                step += 1
            }
        }
    }

    /// Day `dayOfMonth` of the month `months` after `origin`'s month, shortened to fit that month.
    private static func day(_ dayOfMonth: Int, monthsAfter months: Int, from origin: Day) -> Day {
        let index = origin.year * 12 + (origin.month - 1) + months
        let year = index / 12
        let month = index % 12 + 1
        return Day(year, month, min(dayOfMonth, Day.count(inMonth: month, of: year)))
    }
}
