import Foundation

/// A calendar day with no time zone attached.
///
/// Dates in this app are floating (T13): a task planned for Tuesday is planned for Tuesday
/// wherever the user is.
public struct Day: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(parts.year!, parts.month!, parts.day!)
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public func adding(days: Int) -> Day {
        Day(Self.utc.date(byAdding: .day, value: days, to: utcDate)!, in: Self.utc)
    }

    /// The number of days from this day to `other`, negative when `other` is earlier.
    public func days(to other: Day) -> Int {
        Self.utc.dateComponents([.day], from: utcDate, to: other.utcDate).day!
    }

    /// 1 is Sunday and 7 is Saturday, as in `Calendar`.
    public var weekday: Int {
        Self.utc.component(.weekday, from: utcDate)
    }

    public static func count(inMonth month: Int, of year: Int) -> Int {
        utc.range(of: .day, in: .month, for: Day(year, month, 1).utcDate)!.count
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    // Day arithmetic uses a fixed UTC calendar, where no day is ever 23 or 25 hours long.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var utcDate: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

public struct TimeOfDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var hour: Int
    public var minute: Int

    public init(_ hour: Int, _ minute: Int = 0) {
        self.hour = hour
        self.minute = minute
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        (lhs.hour, lhs.minute) < (rhs.hour, rhs.minute)
    }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// A day, optionally with a time of day. With no time it means the whole day (T13).
public struct Moment: Hashable, Codable, Sendable, CustomStringConvertible {
    public var day: Day
    public var time: TimeOfDay?

    public init(_ day: Day, _ time: TimeOfDay? = nil) {
        self.day = day
        self.time = time
    }

    /// The wall-clock day and time of `date` in `calendar`'s time zone.
    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(Day(date, in: calendar), TimeOfDay(parts.hour!, parts.minute!))
    }

    public func adding(days: Int) -> Moment {
        Moment(day.adding(days: days), time)
    }

    /// When this moment begins in `calendar`'s time zone. A whole day begins at its start.
    /// A time that daylight saving skips moves forward to the next valid time.
    public func start(in calendar: Calendar) -> Date {
        let parts = DateComponents(
            year: day.year, month: day.month, day: day.day,
            hour: time?.hour ?? 12, minute: time?.minute ?? 0
        )
        let date = calendar.date(from: parts)!
        return time == nil ? calendar.startOfDay(for: date) : date
    }

    /// When this moment is over: the end of a whole day, or the time itself. Used for deadlines.
    public func end(in calendar: Calendar) -> Date {
        time == nil ? Moment(day.adding(days: 1)).start(in: calendar) : start(in: calendar)
    }

    /// Whether this moment is later than `other`. When either is a whole day only the days are
    /// compared, so a deadline on Tuesday and a start on Tuesday don't conflict.
    func isLater(than other: Moment) -> Bool {
        if day != other.day { return day > other.day }
        guard let time, let otherTime = other.time else { return false }
        return time > otherTime
    }

    /// Orders whole days before timed moments on the same day.
    static func isEarlier(_ lhs: Moment, _ rhs: Moment) -> Bool {
        if lhs.day != rhs.day { return lhs.day < rhs.day }
        switch (lhs.time, rhs.time) {
        case let (left?, right?): return left < right
        case (nil, _?): return true
        default: return false
        }
    }

    public var description: String {
        time.map { "\(day) \($0)" } ?? "\(day)"
    }
}

/// The clock and calendar every rule runs against, so tests can pin both.
public struct Context: Sendable {
    public var now: Date
    public var calendar: Calendar

    public init(now: Date = .now, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public var today: Day {
        Day(now, in: calendar)
    }
}
