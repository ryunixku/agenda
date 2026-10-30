import AgendaCore
import AgendaData
import EventKit
import SwiftUI

/// Tasks with their start dates and deadlines in several time frames (K1), with a toggle for
/// Apple Calendar events (K2). Uses the same dates as the reminders, so the two never disagree.
struct CalendarScreen: View {
    enum Mode: String, CaseIterable, Identifiable {
        case day = "Day", week = "Week", month = "Month", agenda = "Agenda"
        var id: Self { self }
    }

    @Environment(AgendaStore.self) private var store
    @AppStorage("calendar.mode") private var mode = Mode.week
    @State private var anchor = Context().today
    @State private var events = CalendarEvents.shared

    var body: some View {
        NavigationStack {
            let range = range(for: mode)
            let entries = store.agenda.calendar(from: range.lowerBound, through: range.upperBound, at: Context())
            let eventItems = events.items(from: range.lowerBound, through: range.upperBound)
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                if mode != .agenda {
                    header
                }
                switch mode {
                case .day:
                    DayList(days: [anchor], entries: entries, events: eventItems, showsEmptyDays: true)
                case .week:
                    DayList(days: days(range), entries: entries, events: eventItems, showsEmptyDays: true)
                case .month:
                    MonthView(month: anchor, selected: $anchor, entries: entries, events: eventItems)
                case .agenda:
                    DayList(days: days(range), entries: entries, events: eventItems, showsEmptyDays: false)
                }
            }
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { anchor = Context().today }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(isOn: Binding {
                        events.isOn
                    } set: { on in
                        Task { await events.setOn(on) }
                    }) {
                        Label("Apple Calendar", systemImage: events.isOn ? "calendar.badge.checkmark" : "calendar.badge.plus")
                    }
                    .toggleStyle(.button)
                }
            }
            .alert("Calendar access is off", isPresented: $events.denied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Allow Agenda to read your calendars in Settings to see your events here.")
            }
        }
    }

    private var header: some View {
        HStack {
            Button("Previous", systemImage: "chevron.left") { step(-1) }
                .labelStyle(.iconOnly)
            Spacer()
            Text(title)
                .font(.headline)
            Spacer()
            Button("Next", systemImage: "chevron.right") { step(1) }
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }

    private var title: String {
        let date = Moment(anchor).date
        switch mode {
        case .day: return Format.long(anchor)
        case .week:
            let range = range(for: .week)
            return "\(Moment(range.lowerBound).date.formatted(.dateTime.day().month(.abbreviated))) – \(Moment(range.upperBound).date.formatted(.dateTime.day().month(.abbreviated)))"
        case .month, .agenda: return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func step(_ direction: Int) {
        switch mode {
        case .day: anchor = anchor.adding(days: direction)
        case .week: anchor = anchor.adding(days: 7 * direction)
        case .month, .agenda:
            let date = Calendar.current.date(byAdding: .month, value: direction, to: Moment(anchor).date)!
            anchor = Day(date, in: .current)
        }
    }

    private func range(for mode: Mode) -> ClosedRange<Day> {
        switch mode {
        case .day:
            return anchor...anchor
        case .week:
            let offset = (anchor.weekday - Calendar.current.firstWeekday + 7) % 7
            let start = anchor.adding(days: -offset)
            return start...start.adding(days: 6)
        case .month:
            let first = Day(anchor.year, anchor.month, 1)
            return first...Day(anchor.year, anchor.month, Day.count(inMonth: anchor.month, of: anchor.year))
        case .agenda:
            let today = Context().today
            return today...today.adding(days: 60)
        }
    }

    private func days(_ range: ClosedRange<Day>) -> [Day] {
        (0...range.lowerBound.days(to: range.upperBound)).map { range.lowerBound.adding(days: $0) }
    }
}

/// Days stacked in a list, each with its tasks and events.
struct DayList: View {
    let days: [Day]
    let entries: [CalendarEntry]
    let events: [EventItem]
    let showsEmptyDays: Bool

    var body: some View {
        let today = Context().today
        List {
            ForEach(days, id: \.self) { day in
                let dayEntries = entries.filter { $0.covers(day) }
                let dayEvents = events.filter { $0.covers(day) }
                if showsEmptyDays || !dayEntries.isEmpty || !dayEvents.isEmpty {
                    Section {
                        ForEach(dayEvents.filter(\.isAllDay)) { EventRow(event: $0) }
                        ForEach(dayEntries) { CalendarEntryRow(entry: $0, day: day) }
                        ForEach(dayEvents.filter { !$0.isAllDay }) { EventRow(event: $0) }
                        if dayEntries.isEmpty && dayEvents.isEmpty {
                            Text("Nothing planned")
                                .foregroundStyle(.tertiary)
                        }
                    } header: {
                        Text(Format.long(day))
                            .foregroundStyle(day == today ? Color.accentColor : .secondary)
                    }
                }
            }
        }
        .overlay {
            if !showsEmptyDays && entries.isEmpty && events.isEmpty {
                ContentUnavailableView("Nothing coming up", systemImage: "calendar", description: Text("Tasks with dates show up here."))
            }
        }
    }
}

struct MonthView: View {
    let month: Day
    @Binding var selected: Day
    let entries: [CalendarEntry]
    let events: [EventItem]

    var body: some View {
        let first = Day(month.year, month.month, 1)
        let lead = (first.weekday - Calendar.current.firstWeekday + 7) % 7
        let count = Day.count(inMonth: month.month, of: month.year)
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let order = (1...7).sorted { Format.weekdayOrder($0) < Format.weekdayOrder($1) }
        let today = Context().today
        VStack(spacing: 0) {
            Grid(horizontalSpacing: 0, verticalSpacing: 4) {
                GridRow {
                    ForEach(order, id: \.self) { weekday in
                        Text(symbols[weekday - 1])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                let cells = Array(repeating: Day?.none, count: lead) + (1...count).map { Day(month.year, month.month, $0) }
                let rows = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(0..<7, id: \.self) { column in
                            if column < rows[index].count, let day = rows[index][column] {
                                let items = entries.filter { $0.covers(day) }.count + events.filter { $0.covers(day) }.count
                                Button {
                                    selected = day
                                } label: {
                                    VStack(spacing: 3) {
                                        Text("\(day.day)")
                                            .font(.callout.weight(day == today ? .bold : .regular))
                                            .foregroundStyle(day == selected ? .white : (day == today ? Color.accentColor : .primary))
                                            .frame(width: 32, height: 32)
                                            .background(day == selected ? Color.accentColor : .clear, in: .circle)
                                        HStack(spacing: 2) {
                                            ForEach(0..<min(items, 3), id: \.self) { _ in
                                                Circle().frame(width: 5, height: 5)
                                            }
                                        }
                                        .foregroundStyle(.secondary)
                                        .frame(height: 5)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(height: 40)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            DayList(days: [selected], entries: entries, events: events, showsEmptyDays: true)
        }
    }
}

struct CalendarEntryRow: View {
    let entry: CalendarEntry
    let day: Day
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.open(entry.task)
        } label: {
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.title)
                        if entry.isRecurring {
                            Image(systemName: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .foregroundStyle(.primary)
    }

    private var detail: String {
        var parts: [String] = []
        if entry.isSpan {
            let total = entry.firstDay.days(to: entry.lastDay) + 1
            let index = entry.firstDay.days(to: day) + 1
            parts.append("Day \(index) of \(total)")
            if day == entry.lastDay, entry.deadline?.day == day { parts.append("deadline") }
        } else if let start = entry.start, start.day == day {
            parts.append(start.time.map(Format.time) ?? "All day")
            if let deadline = entry.deadline, deadline.day == day, deadline != start {
                parts.append(deadline.time.map { "due \(Format.time($0))" } ?? "deadline")
            }
        } else if let deadline = entry.deadline {
            parts.append(deadline.time.map { "Due \(Format.time($0))" } ?? "Deadline")
        }
        if let planned = entry.plannedDoDate {
            parts.append("moved from \(Format.day(planned.day))")
        }
        return parts.joined(separator: " · ")
    }
}

struct EventRow: View {
    let event: EventItem

    var body: some View {
        HStack(spacing: 10) {
            Capsule()
                .fill(event.color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                Text(event.isAllDay ? "All day · \(event.calendar)" : "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened)) · \(event.calendar)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Apple Calendar events, read-only (K4). Access is asked for when the toggle is first turned on.
@Observable
final class CalendarEvents {
    static let shared = CalendarEvents()

    private let store = EKEventStore()
    private static let key = "calendar.showEvents"

    var isOn = UserDefaults.standard.bool(forKey: key) && EKEventStore.authorizationStatus(for: .event) == .fullAccess
    var denied = false

    func setOn(_ on: Bool) async {
        guard on else {
            isOn = false
            UserDefaults.standard.set(false, forKey: Self.key)
            return
        }
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        isOn = granted
        denied = !granted
        UserDefaults.standard.set(granted, forKey: Self.key)
    }

    func items(from start: Day, through end: Day) -> [EventItem] {
        guard isOn else { return [] }
        let predicate = store.predicateForEvents(withStart: Moment(start).date, end: Moment(end.adding(days: 1)).date, calendars: nil)
        return store.events(matching: predicate).map { event in
            EventItem(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Event",
                start: event.startDate,
                end: event.endDate,
                isAllDay: event.isAllDay,
                calendar: event.calendar?.title ?? "",
                color: Color(cgColor: event.calendar?.cgColor ?? CGColor(gray: 0.5, alpha: 1))
            )
        }
    }
}

struct EventItem: Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendar: String
    let color: Color

    func covers(_ day: Day) -> Bool {
        let dayStart = Moment(day).date
        let dayEnd = Moment(day.adding(days: 1)).date
        return start < dayEnd && end > dayStart
    }
}
