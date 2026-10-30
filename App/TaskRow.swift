import AgendaCore
import AgendaData
import SwiftUI

/// A task in a list: a check button, the title, when it's due, and swipes to act without opening it.
struct TaskRow: View {
    let task: TaskItem
    var showsContainer = false
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let schedule = try? store.agenda.schedule(of: task.id, at: Context())
        let locked = store.agenda.isLocked(task.id)
        HStack(alignment: .center, spacing: 12) {
            CheckButton(task: task, locked: locked)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(locked || task.isArchived ? .secondary : .primary)
                    .lineLimit(2)
                details(schedule, locked: locked)
            }
            Spacer(minLength: 0)
            icons
        }
        .contentShape(.rect)
        .onTapGesture { router.open(task.id) }
        .swipeActions(edge: .leading) {
            if !task.isArchived && !locked {
                Button("Done", systemImage: "checkmark") {
                    TaskActions.complete(task.id, store: store, router: router)
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            if task.isArchived {
                Button("Clone", systemImage: "plus.square.on.square") {
                    TaskActions.clone(task.id, store: store, router: router)
                }
                .tint(.blue)
            } else {
                Button("Tomorrow", systemImage: "sunrise") {
                    TaskActions.reschedule(task.id, to: .tomorrow, store: store, router: router)
                }
                .tint(.blue)
                Button("Tonight", systemImage: "moon") {
                    TaskActions.reschedule(task.id, to: .tonight, store: store, router: router)
                }
                .tint(.indigo)
                Button("Pick", systemImage: "calendar") {
                    router.rescheduling = TaskRef(id: task.id)
                }
                .tint(.gray)
            }
        }
        .contextMenu {
            if !task.isArchived {
                Button("Tonight", systemImage: "moon") { TaskActions.reschedule(task.id, to: .tonight, store: store, router: router) }
                Button("Tomorrow", systemImage: "sunrise") { TaskActions.reschedule(task.id, to: .tomorrow, store: store, router: router) }
                Button("Next week", systemImage: "calendar.badge.clock") { TaskActions.reschedule(task.id, to: .nextWeek, store: store, router: router) }
                Button("Pick a date…", systemImage: "calendar") { router.rescheduling = TaskRef(id: task.id) }
                Divider()
            }
            Button("Clone", systemImage: "plus.square.on.square") { TaskActions.clone(task.id, store: store, router: router) }
        }
    }

    @ViewBuilder
    private func details(_ schedule: Schedule?, locked: Bool) -> some View {
        let parts = detailParts(schedule, locked: locked)
        if !parts.isEmpty {
            HStack(spacing: 4) {
                ForEach(parts.indices, id: \.self) { index in
                    if index > 0 {
                        Text("·").foregroundStyle(.tertiary)
                    }
                    Text(parts[index].text)
                        .foregroundStyle(parts[index].color)
                }
            }
            .font(.caption)
            .lineLimit(1)
        }
    }

    private func detailParts(_ schedule: Schedule?, locked: Bool) -> [(text: String, color: Color)] {
        var parts: [(String, Color)] = []
        if let archived = task.archived {
            let date = archived.at.formatted(date: .abbreviated, time: .omitted)
            parts.append((archived.outcome == .done ? "Done \(date)" : "Closed, not done, \(date)", .secondary))
            return parts
        }
        if locked, let previous = task.previous.flatMap({ store.agenda.tasks[$0] }) {
            parts.append(("After “\(previous.title)”", .secondary))
        } else if locked {
            parts.append(("Waiting", .secondary))
        }
        if let schedule, let doDate = schedule.doDate {
            if schedule.isOverdue {
                parts.append(("\(doDate == schedule.deadline ? "Was due" : "Since") \(Format.moment(doDate))", .red))
            } else {
                parts.append((Format.moment(doDate), .secondary))
            }
            if schedule.isRescheduled, let planned = schedule.plannedStart ?? schedule.plannedDeadline {
                parts.append(("moved from \(Format.day(planned.day))", .secondary))
            }
            if schedule.isPastDeadline, let deadline = schedule.deadline, deadline != doDate {
                parts.append(("past deadline \(Format.day(deadline.day))", .orange))
            } else if let deadline = schedule.deadline, deadline != doDate {
                parts.append(("due \(Format.moment(deadline))", .secondary))
            }
        }
        if showsContainer, task.container != store.agenda.inbox, let container = store.agenda.containers[task.container] {
            parts.append((container.name, .secondary))
        }
        return parts
    }

    private var icons: some View {
        HStack(spacing: 6) {
            let subtasks = store.agenda.subtasks(of: task.id)
            if !subtasks.isEmpty {
                Text("\(subtasks.filter(\.isArchived).count)/\(subtasks.count)")
                    .font(.caption.monospacedDigit())
            }
            if task.plan.recurrence != nil {
                Image(systemName: "repeat")
            }
            if let main = task.mainReminder {
                Image(systemName: main.kind == .alarm || task.reminders.contains { $0.kind == .alarm } ? "alarm" : "bell")
            }
            if !task.blobs.isEmpty {
                Image(systemName: icon(for: task.blobs[0].kind))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct CheckButton: View {
    let task: TaskItem
    var locked = false
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            TaskActions.complete(task.id, store: store, router: router)
        } label: {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(task.isArchived || locked)
        .accessibilityLabel(task.isArchived ? "Done" : "Mark done")
    }

    private var symbol: String {
        if let archived = task.archived { return archived.outcome == .done ? "checkmark.circle.fill" : "xmark.circle" }
        if locked { return "lock.circle" }
        return "circle"
    }

    private var tint: Color {
        if task.archived?.outcome == .done { return .green }
        return .secondary
    }
}

func icon(for kind: BlobRef.Kind) -> String {
    switch kind {
    case .photo: "photo"
    case .scan: "doc.viewfinder"
    case .file: "doc"
    case .voice: "waveform"
    case .link: "link"
    }
}
