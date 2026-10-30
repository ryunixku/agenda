import AgendaCore
import AgendaData
import SwiftUI

/// Everything done, and everything closed without being done (T2, T8). Archived tasks can be
/// searched, viewed and cloned, never restored (T3).
struct ArchiveView: View {
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""

    private enum Item: Identifiable {
        case task(TaskItem)
        case completion(Completion)

        var id: UUID {
            switch self {
            case .task(let task): task.id
            case .completion(let completion): completion.id
            }
        }

        var title: String {
            switch self {
            case .task(let task): task.title
            case .completion(let completion): completion.title
            }
        }

        var date: Date {
            switch self {
            case .task(let task): task.archived?.at ?? task.createdAt
            case .completion(let completion): completion.at
            }
        }
    }

    var body: some View {
        NavigationStack {
            let items = (store.agenda.tasks.values.filter(\.isArchived).map(Item.task)
                + store.agenda.completions.map(Item.completion))
                .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
                .sorted { $0.date > $1.date }
            List(items) { item in
                switch item {
                case .task(let task):
                    TaskRow(task: task, showsContainer: true)
                case .completion(let completion):
                    Button {
                        router.open(completion.task)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(completion.title)
                                Text("Done \(completion.at.formatted(date: .abbreviated, time: .omitted)) · repeat of \(Format.day(completion.occurrence))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "repeat")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .overlay {
                if items.isEmpty {
                    if query.isEmpty {
                        ContentUnavailableView("Nothing archived yet", systemImage: "archivebox", description: Text("Done tasks are kept here for good."))
                    } else {
                        ContentUnavailableView.search(text: query)
                    }
                }
            }
            .searchable(text: $query)
            .navigationTitle("Archive")
        }
    }
}
