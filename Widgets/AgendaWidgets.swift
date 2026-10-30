import SwiftUI
import WidgetKit

@main
struct AgendaWidgets: WidgetBundle {
    var body: some Widget {
        NextTasksWidget()
    }
}

/// Placeholder until the out-of-app surfaces arrive (M6): the next tasks, each with a check button.
struct NextTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTasks", provider: NextTasksProvider()) { _ in
            Text("Nothing to do now")
                .font(.headline)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next tasks")
        .description("What to do next, with a button to tick each one off.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct NextTasksEntry: TimelineEntry {
    let date: Date
}

struct NextTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextTasksEntry {
        NextTasksEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextTasksEntry) -> Void) {
        completion(NextTasksEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextTasksEntry>) -> Void) {
        completion(Timeline(entries: [NextTasksEntry(date: .now)], policy: .never))
    }
}
