import AgendaCore
import AgendaData
import SwiftUI

/// "Pick…": choose a new do date. If it's after the deadline, the deadline can move in the same
/// step, or stay (D4, D7). The plan itself never changes (D1).
struct RescheduleSheet: View {
    let taskID: TaskID
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var date: Date
    @State private var hasTime: Bool
    @State private var deadlineChoice = DeadlineChoice.sameDay
    @State private var newDeadline: Date

    enum DeadlineChoice: Hashable {
        case sameDay, pick, keep
    }

    init(taskID: TaskID, agenda: Agenda) {
        self.taskID = taskID
        let current = (try? agenda.schedule(of: taskID, at: Context()))?.doDate
        let start = current.map { Moment(Context().today.adding(days: 1), $0.time) } ?? Moment(Context().today.adding(days: 1))
        _date = State(initialValue: start.date)
        _hasTime = State(initialValue: start.time != nil)
        _newDeadline = State(initialValue: start.date)
    }

    var body: some View {
        let task = store.agenda.tasks[taskID]
        let deadline = (try? store.agenda.schedule(of: taskID, at: Context()))?.deadline
        let target = Moment(date: date, includingTime: hasTime)
        let pastDeadline = deadline.map { target.day > $0.day } ?? false
        NavigationStack {
            Form {
                Section {
                    DatePicker("Day", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                    Toggle("Time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("Time", selection: $date, displayedComponents: .hourAndMinute)
                    }
                }
                if pastDeadline, let deadline {
                    Section {
                        Picker("Deadline", selection: $deadlineChoice) {
                            Text("Move it to the same day").tag(DeadlineChoice.sameDay)
                            Text("Pick a new deadline").tag(DeadlineChoice.pick)
                            Text("Keep \(Format.moment(deadline))").tag(DeadlineChoice.keep)
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                        if deadlineChoice == .pick {
                            DatePicker("New deadline", selection: $newDeadline, in: date..., displayedComponents: .date)
                        }
                    } header: {
                        Text("That's after the deadline")
                    } footer: {
                        Text("Life happens. Move the deadline too, or keep it and the task shows as past its deadline.")
                    }
                }
            }
            .navigationTitle(task.map { "Move “\($0.title)”" } ?? "Reschedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        var moved: Moment?
                        if pastDeadline, let deadline {
                            switch deadlineChoice {
                            case .sameDay: moved = Moment(target.day, deadline.time.map { max($0, target.time ?? $0) })
                            case .pick: moved = Moment(Day(newDeadline, in: .current), deadline.time)
                            case .keep: moved = nil
                            }
                        }
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in try agenda.reschedule(taskID, to: target, deadline: moved) }
                        }
                        router.showBanner("Moved to \(Format.moment(target))")
                        dismiss()
                    }
                }
            }
        }
    }
}
