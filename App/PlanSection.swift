import AgendaCore
import AgendaData
import SwiftUI

/// The task's own schedule (T1): start, deadline and repeat. Editing here changes the plan;
/// rescheduling never does (D1).
struct PlanSection: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var conflict: Plan?

    var body: some View {
        Section {
            MomentField(title: "Start", moment: binding(\.start))
            MomentField(title: "Deadline", moment: binding(\.deadline))
            RepeatField(task: task, recurrence: binding(\.recurrence))
        } header: {
            Text("Plan")
        } footer: {
            if task.plan.recurrence != nil {
                Text("Missed repeats stay overdue until done, then the task moves to its next date.")
            }
        }
        .alert("The next task starts before this deadline", isPresented: Binding(get: { conflict != nil }, set: { if !$0 { conflict = nil } })) {
            Button("Shift the next tasks") {
                if let conflict { apply(conflict, shifting: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Move the tasks that follow later by as many days as needed?")
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Plan, Value>) -> Binding<Value> {
        Binding {
            store.agenda.tasks[task.id]?.plan[keyPath: keyPath] ?? task.plan[keyPath: keyPath]
        } set: { value in
            var plan = store.agenda.tasks[task.id]?.plan ?? task.plan
            plan[keyPath: keyPath] = value
            apply(plan)
        }
    }

    private func apply(_ plan: Plan, shifting: Bool = false) {
        do throws(RuleViolation) {
            try store.perform { agenda throws(RuleViolation) in try agenda.setPlan(task.id, to: plan, shiftingNext: shifting) }
        } catch {
            if case .sequenceDateConflict(let other) = error, other == store.agenda.nextTask(after: task.id)?.id {
                conflict = plan
            } else {
                router.show(error)
            }
        }
    }
}

/// A day with an optional time (T13).
struct MomentField: View {
    let title: String
    @Binding var moment: Moment?

    var body: some View {
        Toggle(title, isOn: Binding {
            moment != nil
        } set: { on in
            moment = on ? Moment(Context().today) : nil
        })
        if let moment {
            HStack {
                DatePicker("Day", selection: Binding {
                    moment.date
                } set: { date in
                    self.moment = Moment(Day(date, in: .current), moment.time)
                }, displayedComponents: .date)
                .labelsHidden()
                Spacer()
                if let time = moment.time {
                    DatePicker("Time", selection: Binding {
                        Moment(moment.day, time).date
                    } set: { date in
                        self.moment = Moment(date: date, includingTime: true)
                    }, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    Button("No time", systemImage: "xmark.circle.fill") {
                        self.moment = Moment(moment.day)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                } else {
                    Button("Add time") {
                        self.moment = Moment(moment.day, TimeOfDay(9, 0))
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// Repeats on a fixed schedule (T6).
struct RepeatField: View {
    let task: TaskItem
    @Binding var recurrence: Recurrence?

    var body: some View {
        let canRepeat = task.plan.doDate != nil && task.parent == nil && task.previous == nil
        Picker("Repeat", selection: Binding {
            recurrence?.frequency
        } set: { frequency in
            recurrence = frequency.map { Recurrence($0, every: recurrence?.interval ?? 1) }
        }) {
            Text("Never").tag(Recurrence.Frequency?.none)
            Text("Daily").tag(Recurrence.Frequency?.some(.daily))
            Text("Weekly").tag(Recurrence.Frequency?.some(.weekly))
            Text("Monthly").tag(Recurrence.Frequency?.some(.monthly))
            Text("Yearly").tag(Recurrence.Frequency?.some(.yearly))
        }
        .disabled(!canRepeat && recurrence == nil)
        if !canRepeat && recurrence == nil {
            Text(task.plan.doDate == nil ? "Add a start or deadline to repeat this task." : "Subtasks and tasks in a sequence can't repeat.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if let current = recurrence {
            Stepper(Format.recurrence(Recurrence(current.frequency, every: current.interval)), value: Binding {
                current.interval
            } set: { interval in
                var updated = current
                updated.interval = interval
                recurrence = updated
            }, in: 1...99)
            if current.frequency == .weekly {
                // With no days picked, a weekly task repeats on its own weekday, so show that one.
                let own = task.plan.doDate?.day.weekday
                WeekdayPicker(weekdays: Binding {
                    current.weekdays.isEmpty ? Set(own.map { [$0] } ?? []) : current.weekdays
                } set: { days in
                    var updated = current
                    updated.weekdays = days
                    recurrence = updated
                })
            }
            Toggle("Ends", isOn: Binding {
                current.until != nil
            } set: { on in
                var updated = current
                updated.until = on ? (task.plan.doDate?.day ?? Context().today).adding(days: 30) : nil
                recurrence = updated
            })
            if let until = current.until {
                DatePicker("Last day", selection: Binding {
                    Moment(until).date
                } set: { date in
                    var updated = current
                    updated.until = Day(date, in: .current)
                    recurrence = updated
                }, displayedComponents: .date)
            }
        }
    }
}

struct WeekdayPicker: View {
    @Binding var weekdays: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let order = (1...7).sorted { Format.weekdayOrder($0) < Format.weekdayOrder($1) }
        HStack {
            ForEach(order, id: \.self) { weekday in
                let selected = weekdays.contains(weekday)
                Button(symbols[weekday - 1]) {
                    if selected {
                    if weekdays.count > 1 { weekdays.remove(weekday) }
                } else {
                    weekdays.insert(weekday)
                }
                }
                .font(.subheadline.weight(.semibold))
                .frame(width: 34, height: 34)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.15), in: .circle)
                .foregroundStyle(selected ? .white : .primary)
                .buttonStyle(.borderless)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Repeat on")
    }
}
