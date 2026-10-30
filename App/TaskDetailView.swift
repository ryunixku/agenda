import AgendaCore
import AgendaData
import SwiftUI

/// A task's details, as a sheet so the user is never deep in navigation (ARCHITECTURE §3.6).
struct TaskDetailView: View {
    let taskID: TaskID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TaskDetailForm(taskID: taskID)
                .navigationDestination(for: TaskRef.self) { TaskDetailForm(taskID: $0.id) }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                    }
                }
        }
    }
}

struct TaskDetailForm: View {
    let taskID: TaskID
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var newNote = ""
    @State private var confirmDelete = false

    var body: some View {
        if let task = store.agenda.tasks[taskID] {
            form(task)
                .navigationTitle(task.isArchived ? "Archived" : (task.parent == nil ? "Task" : "Subtask"))
                .navigationBarTitleDisplayMode(.inline)
                .onAppear { title = task.title }
                .onChange(of: task.title) { _, new in title = new }
        } else {
            ContentUnavailableView("This task was deleted", systemImage: "trash")
        }
    }

    private func form(_ task: TaskItem) -> some View {
        let context = Context()
        let schedule = try? store.agenda.schedule(of: task.id, at: context)
        let locked = store.agenda.isLocked(task.id)
        return Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    CheckButton(task: task, locked: locked)
                        .padding(.top, 2)
                    TextField("Title", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .disabled(task.isArchived)
                        .onSubmit { rename(task) }
                        .submitLabel(.done)
                }
                status(task, schedule: schedule, locked: locked)
                if !task.isArchived {
                    quickActions(task, locked: locked)
                }
            }

            if task.isArchived {
                Section {
                    Button("Clone as a new task", systemImage: "plus.square.on.square") {
                        TaskActions.clone(task.id, store: store, router: router)
                    }
                } footer: {
                    Text("Archived tasks can't be changed or restored. A clone starts fresh with the same details.")
                }
            }

            PlanSection(task: task)
                .disabled(task.isArchived)

            RemindersSection(task: task)
                .disabled(task.isArchived)

            if task.parent == nil && task.plan.recurrence == nil {
                SubtasksSection(task: task)
            }

            if task.parent == nil && task.plan.recurrence == nil && !task.isArchived {
                SequenceSection(task: task)
            }

            Section("Notes") {
                ForEach(task.notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.text)
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        if !task.isArchived {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                TaskActions.attempt(router) {
                                    try store.perform { agenda throws(RuleViolation) in try agenda.removeNote(note.id, from: .task(task.id)) }
                                }
                            }
                        }
                    }
                }
                if !task.isArchived {
                    TextField("Add a note", text: $newNote, axis: .vertical)
                        .onSubmit { addNote(task) }
                        .submitLabel(.done)
                }
            }

            AttachmentsSection(task: task)

            if task.parent == nil && !task.isArchived {
                Section {
                    Picker("List or project", selection: containerBinding(task)) {
                        ForEach(containerChoices) { container in
                            Label(container.name, systemImage: container.isInbox ? "tray" : container.kind == .project ? "flag" : "list.bullet")
                                .tag(container.id)
                        }
                    }
                }
            }

            Section {
                if !task.isArchived {
                    Button("Clone", systemImage: "plus.square.on.square") {
                        TaskActions.clone(task.id, store: store, router: router)
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    confirmDelete = true
                }
                .foregroundStyle(.red)
            }
        }
        .onDisappear { rename(task) }
        .confirmationDialog("Delete “\(task.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete for good", role: .destructive) {
                TaskActions.delete(task.id, store: store, router: router)
                dismiss()
            }
        } message: {
            Text(store.agenda.subtasks(of: task.id).isEmpty
                 ? "This can't be undone."
                 : "Its subtasks are deleted too. This can't be undone.")
        }
    }

    @ViewBuilder
    private func status(_ task: TaskItem, schedule: Schedule?, locked: Bool) -> some View {
        if let archived = task.archived {
            Label(
                archived.outcome == .done
                    ? "Done on \(archived.at.formatted(date: .long, time: .shortened))"
                    : "Closed, not done, on \(archived.at.formatted(date: .long, time: .shortened))",
                systemImage: archived.outcome == .done ? "checkmark.circle.fill" : "xmark.circle"
            )
            .foregroundStyle(.secondary)
        }
        if locked {
            let previous = task.previous.flatMap { store.agenda.tasks[$0] }
                ?? task.parent.flatMap { store.agenda.tasks[$0] }.flatMap { $0.previous }.flatMap { store.agenda.tasks[$0] }
            Label("Waiting for “\(previous?.title ?? "the task before")”", systemImage: "lock")
                .foregroundStyle(.secondary)
        }
        if let schedule, !task.isArchived {
            if schedule.isRescheduled, let doDate = schedule.doDate {
                let planned = (schedule.plannedStart ?? schedule.plannedDeadline).map { " (planned \(Format.moment($0)))" } ?? ""
                Label("Moved to \(Format.moment(doDate))\(planned)", systemImage: "arrow.uturn.forward")
                    .foregroundStyle(.secondary)
            }
            if schedule.isOverdue, let doDate = schedule.doDate {
                Label("Overdue since \(Format.moment(doDate))", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
            }
            if schedule.isPastDeadline, let deadline = schedule.deadline {
                Label("Past the deadline, \(Format.moment(deadline))", systemImage: "flag")
                    .foregroundStyle(.orange)
            }
        }
    }

    private func quickActions(_ task: TaskItem, locked: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                TaskActions.complete(task.id, store: store, router: router)
            } label: {
                Label("Done", systemImage: "checkmark")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(locked)

            Menu {
                Button("Tonight", systemImage: "moon") { TaskActions.reschedule(task.id, to: .tonight, store: store, router: router) }
                Button("Tomorrow", systemImage: "sunrise") { TaskActions.reschedule(task.id, to: .tomorrow, store: store, router: router) }
                Button("Next week", systemImage: "calendar.badge.clock") { TaskActions.reschedule(task.id, to: .nextWeek, store: store, router: router) }
                Button("Pick a date…", systemImage: "calendar") { router.rescheduling = TaskRef(id: task.id) }
            } label: {
                Label("Move", systemImage: "arrow.uturn.forward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .buttonStyle(.borderless)
        .controlSize(.large)
    }

    private var containerChoices: [Container] {
        let active = store.agenda.containers.values.filter { $0.archived == nil }
        return active.filter(\.isInbox)
            + active.filter { !$0.isInbox && $0.kind == .list }.sorted { $0.name < $1.name }
            + active.filter { $0.kind == .project }.sorted { $0.name < $1.name }
    }

    private func containerBinding(_ task: TaskItem) -> Binding<ContainerID> {
        Binding {
            task.container
        } set: { container in
            TaskActions.attempt(router) {
                try store.perform { agenda throws(RuleViolation) in try agenda.move(task.id, to: container) }
            }
        }
    }

    private func rename(_ task: TaskItem) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.isArchived, !trimmed.isEmpty, trimmed != task.title, store.agenda.tasks[task.id] != nil else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.rename(task.id, to: trimmed) }
        }
    }

    private func addNote(_ task: TaskItem) {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.addNote(text, to: .task(task.id), at: Context()) }
        }
        newNote = ""
    }
}

struct SubtasksSection: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var newSubtask = ""

    var body: some View {
        let subtasks = store.agenda.subtasks(of: task.id)
        Section {
            ForEach(subtasks) { subtask in
                NavigationLink(value: TaskRef(id: subtask.id)) {
                    HStack(spacing: 12) {
                        CheckButton(task: subtask, locked: store.agenda.isLocked(subtask.id))
                        Text(subtask.title)
                            .foregroundStyle(subtask.isArchived || store.agenda.isLocked(subtask.id) ? .secondary : .primary)
                    }
                }
            }
            if !task.isArchived {
                TextField("Add a subtask", text: $newSubtask)
                    .onSubmit(add)
                    .submitLabel(.next)
                if subtasks.filter({ !$0.isArchived }).count > 1 {
                    Toggle("Do in order", isOn: Binding {
                        store.agenda.subtasksInOrder(of: task.id)
                    } set: { inOrder in
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in try agenda.setSubtasksInOrder(inOrder, of: task.id) }
                        }
                    })
                }
            }
        } header: {
            Text("Subtasks")
        } footer: {
            if !subtasks.isEmpty && !task.isArchived {
                Text("When every subtask is done, this task is done too. “Do in order” unlocks each step when the one before is done.")
            }
        }
    }

    private func add() {
        let title = newSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.addSubtask(title, to: task.id, at: Context()) }
        }
        newSubtask = ""
    }
}

/// "Comes after": B stays locked until A is done (S4).
struct SequenceSection: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        Section {
            if let previous = task.previous.flatMap({ store.agenda.tasks[$0] }) {
                HStack {
                    LabeledContent("After", value: previous.title)
                    Button("Remove", systemImage: "xmark.circle.fill") {
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in try agenda.unlink(task.id) }
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            } else {
                NavigationLink("Comes after…") {
                    TaskPicker(title: "Comes after", candidates: candidates) { chosen in
                        TaskActions.attempt(router) {
                            try store.perform { agenda throws(RuleViolation) in try agenda.link(chosen, then: task.id) }
                        }
                    }
                }
            }
            if let next = store.agenda.nextTask(after: task.id) {
                LabeledContent("Then", value: next.title)
            }
        } header: {
            Text("Sequence")
        } footer: {
            Text("A task in a sequence stays locked until the one before it is done. Its deadline can't be later than the next task's start.")
        }
    }

    private var candidates: [TaskItem] {
        store.agenda.tasks.values
            .filter { other in
                other.id != task.id && !other.isArchived && other.parent == nil && other.plan.recurrence == nil
                    && store.agenda.nextTask(after: other.id) == nil
            }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }
}

struct TaskPicker: View {
    let title: String
    let candidates: [TaskItem]
    let onPick: (TaskID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        List(candidates.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { task in
            Button(task.title) {
                onPick(task.id)
                dismiss()
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if candidates.isEmpty {
                ContentUnavailableView("No tasks to choose", systemImage: "list.bullet")
            }
        }
        .searchable(text: $query)
        .navigationTitle(title)
    }
}
