import ActivityKit
import AgendaCore
import AgendaData
import AlarmKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AgendaWidgets: WidgetBundle {
    var body: some Widget {
        NextTasksWidget()
        TaskLiveActivity()
        AlarmLiveActivity()
        CaptureControl()
    }
}

// MARK: Next tasks, with a button to tick each one off without opening the app

struct NextTasksEntry: TimelineEntry {
    struct Item: Identifiable {
        let id: TaskID
        let title: String
        let detail: String
        let overdue: Bool
    }

    let date: Date
    let items: [Item]
    let total: Int
}

struct NextTasksProvider: TimelineProvider {
    func placeholder(in context: TimelineProviderContext) -> NextTasksEntry {
        NextTasksEntry(date: .now, items: [
            .init(id: UUID(), title: "Call the bank", detail: "10:00", overdue: false),
            .init(id: UUID(), title: "Buy milk", detail: "Today", overdue: false),
        ], total: 2)
    }

    func getSnapshot(in context: TimelineProviderContext, completion: @escaping (NextTasksEntry) -> Void) {
        Task { @MainActor in completion(Self.entry()) }
    }

    func getTimeline(in context: TimelineProviderContext, completion: @escaping (Timeline<NextTasksEntry>) -> Void) {
        Task { @MainActor in
            let entry = Self.entry()
            // Refresh after midnight, when "today" changes, and every half hour in between.
            let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(24 * 60 * 60))
            completion(Timeline(entries: [entry], policy: .after(min(midnight, .now.addingTimeInterval(30 * 60)))))
        }
    }

    @MainActor
    static func entry() -> NextTasksEntry {
        let store = SharedStore.shared
        store.reload()
        let context = AgendaCore.Context()
        let tasks = store.agenda.actionable(at: context)
        let items = tasks.prefix(6).map { task in
            let schedule = try? store.agenda.schedule(of: task.id, at: context)
            let detail: String = {
                guard let doDate = schedule?.doDate else { return "" }
                if schedule?.isOverdue == true { return "Since \(Format.day(doDate.day))" }
                return doDate.time.map(Format.time) ?? "Today"
            }()
            return NextTasksEntry.Item(id: task.id, title: task.title, detail: detail, overdue: schedule?.isOverdue == true)
        }
        return NextTasksEntry(date: .now, items: Array(items), total: tasks.count)
    }
}

struct NextTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextTasks", provider: NextTasksProvider()) { entry in
            NextTasksView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next tasks")
        .description("What to do now, with a button to tick each one off.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

struct NextTasksView: View {
    let entry: NextTasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let limit = switch family {
        case .systemSmall, .accessoryRectangular: 3
        case .systemLarge: 6
        default: 4
        }
        VStack(alignment: .leading, spacing: family == .accessoryRectangular ? 2 : 6) {
            if family != .accessoryRectangular {
                HStack {
                    Text("Now")
                        .font(.headline)
                    Spacer()
                    if entry.total > 0 {
                        Text("\(entry.total)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Label("Nothing to do now", systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ForEach(entry.items.prefix(limit)) { item in
                    HStack(spacing: 8) {
                        Button(intent: CompleteTaskIntent(task: TaskEntity(id: item.id, title: item.title))) {
                            Image(systemName: "circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(item.overdue ? .red : .secondary)
                        Link(destination: URL(string: "agenda://task/\(item.id.uuidString)")!) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title)
                                    .font(family == .accessoryRectangular ? .caption : .subheadline)
                                    .lineLimit(1)
                                if family != .systemSmall && family != .accessoryRectangular && !item.detail.isEmpty {
                                    Text(item.detail)
                                        .font(.caption2)
                                        .foregroundStyle(item.overdue ? .red : .secondary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .widgetURL(URL(string: "agenda://capture"))
    }
}

// MARK: Sticky reminders on the Lock Screen and in the Dynamic Island (R6)

struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    Text(context.state.due, style: .time)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ActivityButtons(attributes: context.attributes)
            }
            .padding()
            .activityBackgroundTint(Color(.systemBackground).opacity(0.6))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(.orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityButtons(attributes: context.attributes)
                }
            } compactLeading: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                Text(context.attributes.title)
                    .lineLimit(1)
                    .frame(maxWidth: 64)
            } minimal: {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.orange)
            }
            .widgetURL(URL(string: "agenda://task/\(context.attributes.taskID.uuidString)"))
        }
    }
}

struct ActivityButtons: View {
    let attributes: TaskActivityAttributes

    var body: some View {
        let task = TaskEntity(id: attributes.taskID, title: attributes.title)
        HStack(spacing: 8) {
            Button(intent: CompleteTaskIntent(task: task)) {
                Label("Done", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .tint(.green)
            Button(intent: RescheduleTaskIntent(task: task, when: .tonight)) {
                Label("Tonight", systemImage: "moon")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: RescheduleTaskIntent(task: task, when: .tomorrow)) {
                Label("Tomorrow", systemImage: "sunrise")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .font(.caption.weight(.semibold))
    }
}

// MARK: Alarms (R7): AlarmKit shows these while counting down or ringing

struct AlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TaskAlarmMetadata>.self) { context in
            HStack {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
                Text(context.attributes.presentation.alert.title)
                    .font(.headline)
                Spacer()
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.presentation.alert.title)
                }
            } compactLeading: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                EmptyView()
            } minimal: {
                Image(systemName: "alarm.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

// MARK: Capture from Control Center or the Action button

struct CaptureControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "CaptureControl") {
            ControlWidgetButton(action: OpenCaptureIntent()) {
                Label("Add to Agenda", systemImage: "plus.circle")
            }
        }
        .displayName("Add to Agenda")
        .description("Opens Agenda ready to add a task.")
    }
}
