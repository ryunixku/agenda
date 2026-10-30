import Foundation
@testable import AgendaCore

let madrid = "Europe/Madrid"
let newYork = "America/New_York"
let tokyo = "Asia/Tokyo"

func calendar(_ zone: String = madrid) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    calendar.firstWeekday = 2
    return calendar
}

/// A context at a wall-clock time in `zone`. Defaults to noon in Madrid.
func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, in zone: String = madrid) -> Context {
    let calendar = calendar(zone)
    let now = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    return Context(now: now, calendar: calendar)
}

/// A day, or a day and time when `hour` is given.
func moment(_ year: Int, _ month: Int, _ day: Int, _ hour: Int? = nil, _ minute: Int = 0) -> Moment {
    Moment(Day(year, month, day), hour.map { TimeOfDay($0, minute) })
}

/// The wall-clock time of `date` in `zone`, such as "2026-11-02 09:30".
func wall(_ date: Date, in zone: String = madrid) -> String {
    let parts = calendar(zone).dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return String(format: "%04d-%02d-%02d %02d:%02d", parts.year!, parts.month!, parts.day!, parts.hour!, parts.minute!)
}

// In the tests, 2 November 2026 is a Monday.
let thursdayBefore = at(2026, 10, 29)
