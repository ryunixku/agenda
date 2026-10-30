import AgendaCore
import AgendaData
import AlarmKit
import SwiftUI

/// One main reminder, the others counting from it (R1, R3). Each is a sticky notification or an
/// alarm (R2). Permission is asked for when the first reminder is added.
struct RemindersSection: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var pickingTime = false

    var body: some View {
        let times = store.agenda.reminderTimes(for: task.id, at: Context())
        Section {
            if let main = task.mainReminder {
                ReminderRow(task: task, reminder: main, isMain: true, date: times.first { $0.reminder == main.id }?.date)
            }
            ForEach(task.reminders) { reminder in
                ReminderRow(task: task, reminder: reminder, isMain: false, date: times.first { $0.reminder == reminder.id }?.date)
            }
            if !task.isArchived {
                Menu {
                    if task.mainReminder == nil {
                        if (try? store.agenda.schedule(of: task.id, at: Context()))?.doDate != nil {
                            add(.minutes(0), "At the time of the task")
                            add(.minutes(-10), "10 minutes before")
                            add(.minutes(-30), "30 minutes before")
                            add(.minutes(-60), "1 hour before")
                            add(.on(days: 0, at: TimeOfDay(9, 0)), "On the day at 9:00")
                            add(.on(days: -1, at: TimeOfDay(18, 0)), "The day before at 18:00")
                        }
                    } else {
                        add(.minutes(-10), "10 minutes before the main one")
                        add(.minutes(-60), "1 hour before the main one")
                        add(.days(-1), "1 day before the main one")
                        add(.days(-7), "1 week before the main one")
                    }
                    Button("Pick a day and time…", systemImage: "calendar") { pickingTime = true }
                } label: {
                    Label("Add reminder", systemImage: "plus")
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            if task.mainReminder != nil {
                let hasAlarm = ([task.mainReminder] + task.reminders.map(Optional.some)).contains { $0?.kind == .alarm }
                if hasAlarm && AlarmManager.shared.authorizationState == .denied {
                    Text("Alarms are turned off for Agenda, so alarm reminders arrive as sticky notifications instead. You can allow alarms in Settings.")
                } else {
                    Text("Every reminder follows the main one, and they all move when you reschedule. Sticky reminders repeat every 10 minutes until you act; alarms ring even in Silent mode.")
                }
            }
        }
        .sheet(isPresented: $pickingTime) {
            ReminderTimeSheet(task: task)
                .presentationDetents([.medium])
        }
    }

    private func add(_ offset: ReminderOffset, _ title: String) -> some View {
        Button(title) {
            TaskActions.attempt(router) {
                try store.perform { agenda throws(RuleViolation) in try agenda.addReminder(.sticky, offset, to: task.id) }
            }
            Task { await ReminderEngine.shared.requestNotificationPermission() }
        }
    }
}

struct ReminderRow: View {
    let task: TaskItem
    let reminder: Reminder
    let isMain: Bool
    let date: Date?
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.kind == .alarm ? "alarm" : "bell.badge")
                .foregroundStyle(reminder.kind == .alarm ? .orange : .accentColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(Format.reminder(reminder.offset, isMain: isMain))
                HStack(spacing: 4) {
                    if isMain { Text("Main ·") }
                    Text(reminder.kind == .alarm ? "Alarm" : "Sticky")
                    if let date {
                        Text("· \(Format.moment(Moment(date, in: .current)))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if !task.isArchived {
                Menu {
                    Picker("Kind", selection: Binding {
                        reminder.kind
                    } set: { kind in
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in try agenda.setKind(kind, ofReminder: reminder.id, on: task.id) }
                        }
                        Task {
                            if kind == .alarm { await ReminderEngine.shared.requestAlarmPermission() }
                            await ReminderEngine.shared.requestNotificationPermission()
                        }
                    }) {
                        Label("Sticky notification", systemImage: "bell.badge").tag(Reminder.Kind.sticky)
                        Label("Alarm", systemImage: "alarm").tag(Reminder.Kind.alarm)
                    }
                    Button("Remove", systemImage: "trash", role: .destructive) { remove() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .swipeActions {
            if !task.isArchived {
                Button("Remove", systemImage: "trash", role: .destructive) { remove() }
            }
        }
    }

    private func remove() {
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.removeReminder(reminder.id, from: task.id, at: Context()) }
        }
    }
}

/// "Remind me on Thursday at 9:00". On a task with no date, this also sets its start (R8).
struct ReminderTimeSheet: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date.now.addingTimeInterval(60 * 60)
    @State private var kind = Reminder.Kind.sticky

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("When", selection: $date)
                Picker("Kind", selection: $kind) {
                    Text("Sticky notification").tag(Reminder.Kind.sticky)
                    Text("Alarm").tag(Reminder.Kind.alarm)
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in
                                try agenda.addReminder(kind, on: Moment(date: date, includingTime: true), to: task.id, at: Context())
                            }
                        }
                        Task {
                            if kind == .alarm { await ReminderEngine.shared.requestAlarmPermission() }
                            await ReminderEngine.shared.requestNotificationPermission()
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}
