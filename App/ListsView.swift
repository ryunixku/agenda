import AgendaCore
import AgendaData
import SwiftUI

/// The Inbox, lists (never end) and projects (meant to be finished) (C1, C4).
struct ListsView: View {
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var adding: Container.Kind?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            let containers = store.agenda.containers.values
            let lists = containers.filter { $0.kind == .list && !$0.isInbox }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            let projects = containers.filter { $0.kind == .project && $0.archived == nil }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            let finished = containers.filter { $0.kind == .project && $0.archived != nil }.sorted { $0.archived!.at > $1.archived!.at }
            List {
                if let inbox = store.agenda.containers[store.agenda.inbox] {
                    Section {
                        ContainerRow(container: inbox)
                    } footer: {
                        Text("Where new tasks land until you put them in a list or project.")
                    }
                }
                Section("Lists") {
                    ForEach(lists) { ContainerRow(container: $0) }
                    Button("New list", systemImage: "plus") { startAdding(.list) }
                }
                Section("Projects") {
                    ForEach(projects) { ContainerRow(container: $0) }
                    Button("New project", systemImage: "plus") { startAdding(.project) }
                }
                if !finished.isEmpty {
                    Section("Finished projects") {
                        ForEach(finished) { ContainerRow(container: $0) }
                    }
                }
            }
            .navigationTitle("Lists & Projects")
            .navigationDestination(for: ContainerID.self) { ContainerView(containerID: $0) }
            .alert(adding == .project ? "New project" : "New list", isPresented: Binding(get: { adding != nil }, set: { if !$0 { adding = nil } })) {
                TextField("Name", text: $name)
                Button("Add") { add() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(adding == .project ? "Projects are meant to be finished." : "Lists never end, like Groceries or Home.")
            }
        }
    }

    private func startAdding(_ kind: Container.Kind) {
        name = ""
        adding = kind
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let kind = adding else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda in
                kind == .project ? agenda.addProject(trimmed) : agenda.addList(trimmed)
            }
        }
    }
}

struct ContainerRow: View {
    let container: Container
    @Environment(AgendaStore.self) private var store

    var body: some View {
        let tasks = store.agenda.tasks.values.filter { $0.container == container.id && $0.parent == nil }
        let open = tasks.filter { !$0.isArchived }.count
        NavigationLink(value: container.id) {
            HStack {
                Label(container.name, systemImage: symbol)
                Spacer()
                if container.kind == .project && !tasks.isEmpty {
                    ProgressRing(fraction: Double(tasks.count - open) / Double(tasks.count))
                }
                if open > 0 {
                    Text("\(open)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private var symbol: String {
        if container.isInbox { return "tray" }
        if container.kind == .project { return container.archived == nil ? "flag" : "flag.checkered" }
        return "list.bullet"
    }
}

/// One list or project: its tasks with their subtasks, its standalone notes (N2), and what's done.
struct ContainerView: View {
    let containerID: ContainerID
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var renaming = false
    @State private var name = ""
    @State private var newNote = ""
    @State private var confirmFinish = false

    var body: some View {
        if let container = store.agenda.containers[containerID] {
            content(container)
        } else {
            ContentUnavailableView("Not found", systemImage: "questionmark.folder")
        }
    }

    private func content(_ container: Container) -> some View {
        let tasks = store.agenda.tasks.values.filter { $0.container == containerID && $0.parent == nil }
        let open = tasks.filter { !$0.isArchived }.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }
        let done = tasks.filter(\.isArchived).sorted { $0.archived!.at > $1.archived!.at }
        let finished = container.archived != nil
        return List {
            if !open.isEmpty {
                Section {
                    ForEach(open) { task in
                        TaskRow(task: task)
                        ForEach(store.agenda.subtasks(of: task.id).filter { !$0.isArchived }) { subtask in
                            TaskRow(task: subtask)
                                .padding(.leading, 28)
                        }
                    }
                }
            }
            Section("Notes") {
                ForEach(container.notes) { note in
                    Text(note.text)
                        .swipeActions {
                            if !finished {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    TaskActions.attempt(router) {
                                        try store.perform { agenda throws(RuleViolation) in try agenda.removeNote(note.id, from: .container(containerID)) }
                                    }
                                }
                            }
                        }
                }
                if !finished {
                    TextField("Add a note", text: $newNote, axis: .vertical)
                        .submitLabel(.done)
                        .onSubmit(addNote)
                }
            }
            if !done.isEmpty {
                Section("Done") {
                    DisclosureGroup("\(done.count) archived") {
                        ForEach(done) { TaskRow(task: $0) }
                    }
                }
            }
        }
        .overlay {
            if open.isEmpty && container.notes.isEmpty && done.isEmpty {
                ContentUnavailableView(
                    container.isInbox ? "Inbox is empty" : "Nothing here yet",
                    systemImage: container.isInbox ? "tray" : "checklist",
                    description: Text(finished ? "This project is finished." : "Add a task below.")
                )
            }
        }
        .navigationTitle(container.name)
        .toolbar {
            if !container.isInbox && !finished {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        name = container.name
                        renaming = true
                    }
                    if container.kind == .project {
                        Button("Finish project", systemImage: "flag.checkered") {
                            if open.isEmpty {
                                TaskActions.finish(project: containerID, store: store, router: router)
                            } else {
                                confirmFinish = true
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !finished {
                CaptureBar(container: containerID)
            }
        }
        .alert("Rename", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Save") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                TaskActions.attempt(router) {
                    try store.perform { agenda throws(RuleViolation) in try agenda.rename(container: containerID, to: trimmed) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Finish “\(container.name)”?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish project") {
                TaskActions.finish(project: containerID, store: store, router: router)
            }
        } message: {
            Text("\(open.count) open \(open.count == 1 ? "task is" : "tasks are") archived with it as not done. You can mark them done right after.")
        }
    }

    private func addNote() {
        let text = newNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.addNote(text, to: .container(containerID), at: Context()) }
        }
        newNote = ""
    }
}

/// How much of a project is done.
struct ProgressRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 3)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("\(Int(fraction * 100)) percent done")
    }
}
