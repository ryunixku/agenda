import AgendaCore
import AgendaData
import SwiftUI

/// What can be done now: overdue first, then today (S9). Capture is always ready at the bottom.
struct NowView: View {
    @Environment(AgendaStore.self) private var store

    var body: some View {
        NavigationStack {
            let context = Context()
            let tasks = store.agenda.actionable(at: context)
            let overdue = tasks.filter { (try? store.agenda.schedule(of: $0.id, at: context))?.isOverdue == true }
            let today = tasks.filter { !overdue.contains($0) }
            // Just-captured tasks with no date, newest first, so capture always shows its result.
            let inbox = store.agenda.tasks.values
                .filter { $0.container == store.agenda.inbox && $0.parent == nil && !$0.isArchived && $0.plan.doDate == nil && $0.rescheduled == nil }
                .sorted { $0.createdAt > $1.createdAt }
            List {
                if !overdue.isEmpty {
                    Section("Overdue") {
                        ForEach(overdue) { TaskRow(task: $0, showsContainer: true) }
                    }
                }
                if !today.isEmpty {
                    Section("Today") {
                        ForEach(today) { TaskRow(task: $0, showsContainer: true) }
                    }
                }
                if !inbox.isEmpty {
                    Section {
                        ForEach(inbox.prefix(5)) { TaskRow(task: $0) }
                        if inbox.count > 5 {
                            NavigationLink("All \(inbox.count) in the Inbox", value: store.agenda.inbox)
                        }
                    } header: {
                        Text("Inbox")
                    } footer: {
                        Text("No date yet. Swipe left to plan it, or open it to put it in a list.")
                    }
                }
            }
            .overlay {
                if tasks.isEmpty && inbox.isEmpty {
                    ContentUnavailableView(
                        "Nothing to do now",
                        systemImage: "checkmark.circle",
                        description: Text("Add a task below, or enjoy the free time.")
                    )
                }
            }
            .navigationTitle("Now")
            .navigationDestination(for: ContainerID.self) { ContainerView(containerID: $0) }
            .safeAreaInset(edge: .bottom) {
                CaptureBar(container: nil)
            }
        }
    }
}
