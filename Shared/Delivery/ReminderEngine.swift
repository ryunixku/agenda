import ActivityKit
import AgendaCore
import AlarmKit
import CryptoKit
import Foundation
import OSLog
import SwiftUI
import UserNotifications

/// Keeps what iOS has scheduled in line with the data (ARCHITECTURE §3.3).
///
/// Each run works out every delivery that should exist, compares it with what iOS has, and adds
/// or removes the difference. Every delivery has a stable ID, so running twice changes nothing.
final class ReminderEngine {
    static let shared = ReminderEngine()

    /// A sticky reminder repeats until acted on (R6).
    static let stickyRepeats = 6
    static let stickyInterval: TimeInterval = 10 * 60
    /// iOS keeps at most 64 pending notifications per app; leave room.
    static let notificationBudget = 60
    /// Live Activities scheduled ahead of time. iOS allows only a few at once.
    static let activityBudget = 3

    static let category = "task"

    enum Action: String {
        case done, tonight, tomorrow, pick
    }

    static var categories: Set<UNNotificationCategory> {
        let actions = [
            UNNotificationAction(identifier: Action.done.rawValue, title: "Done", options: [], icon: .init(systemImageName: "checkmark")),
            UNNotificationAction(identifier: Action.tonight.rawValue, title: "Tonight", options: [], icon: .init(systemImageName: "moon")),
            UNNotificationAction(identifier: Action.tomorrow.rawValue, title: "Tomorrow", options: [], icon: .init(systemImageName: "sunrise")),
            UNNotificationAction(identifier: Action.pick.rawValue, title: "Pick…", options: [.foreground], icon: .init(systemImageName: "calendar")),
        ]
        return [UNNotificationCategory(identifier: category, actions: actions, intentIdentifiers: [], options: [])]
    }

    private var isRunning = false
    private var runAgain = false
    private let log = Logger(subsystem: "Agenda", category: "reminders")

    /// Brings iOS in line with `agenda`. Calls made while a run is going are folded into one more run.
    func reconcile(_ agenda: Agenda) async {
        if isRunning {
            runAgain = true
            return
        }
        isRunning = true
        defer { isRunning = false }
        var latest = agenda
        repeat {
            runAgain = false
            let plan = Self.plan(latest, at: Context(), alarmsAllowed: AlarmManager.shared.authorizationState == .authorized)
            await reconcileNotifications(plan.notifications, agenda: latest)
            await reconcileAlarms(plan.alarms)
            await reconcileActivities(plan.activities)
            log.info("Reminders reconciled: \(plan.notifications.count) notifications, \(plan.alarms.count) alarms, \(plan.activities.count) Live Activities wanted")
            latest = SharedStore.shared.agenda
        } while runAgain
    }

    // MARK: Permissions, asked for when the feature is first used

    /// Asks once, then schedules what was waiting for permission.
    func requestNotificationPermission() async {
        let center = UNUserNotificationCenter.current()
        if await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            await reconcile(SharedStore.shared.agenda)
        }
    }

    func requestAlarmPermission() async {
        if AlarmManager.shared.authorizationState == .notDetermined {
            _ = try? await AlarmManager.shared.requestAuthorization()
            await reconcile(SharedStore.shared.agenda)
        }
    }

    // MARK: What should exist

    struct Plan {
        var notifications: [PlannedNotification] = []
        var alarms: [PlannedAlarm] = []
        var activities: [PlannedActivity] = []
    }

    struct PlannedNotification: Hashable {
        var id: String
        var task: TaskID
        var title: String
        var body: String
        var date: Date
        var sticky: Bool
    }

    struct PlannedAlarm: Hashable {
        var id: UUID
        var task: TaskID
        var title: String
        var date: Date
    }

    struct PlannedActivity: Hashable {
        var key: String
        var task: TaskID
        var title: String
        var date: Date
    }

    /// Every delivery that should exist. Without alarm permission, alarms become sticky
    /// notifications, so a reminder never goes silent.
    static func plan(_ agenda: Agenda, at context: Context, alarmsAllowed: Bool) -> Plan {
        var plan = Plan()
        for task in agenda.tasks.values where !task.isArchived {
            for time in agenda.reminderTimes(for: task.id, at: context) {
                let stamp = Int(time.date.timeIntervalSince1970)
                let key = "\(time.key)@\(stamp)"
                switch time.kind {
                case .alarm where alarmsAllowed:
                    if time.date > context.now {
                        plan.alarms.append(PlannedAlarm(id: uuid(for: key), task: task.id, title: task.title, date: time.date))
                    }
                case .alarm, .sticky:
                    for index in 0...stickyRepeats {
                        let date = time.date.addingTimeInterval(Double(index) * stickyInterval)
                        guard date > context.now else { continue }
                        plan.notifications.append(PlannedNotification(
                            id: "\(key)#\(index)",
                            task: task.id,
                            title: task.title,
                            body: index == 0 ? "Reminder" : "Still to do",
                            date: date,
                            sticky: true
                        ))
                    }
                    if time.date > context.now {
                        plan.activities.append(PlannedActivity(key: key, task: task.id, title: task.title, date: time.date))
                    }
                }
            }
        }
        plan.notifications = Array(plan.notifications.sorted { $0.date < $1.date }.prefix(notificationBudget))
        plan.activities = Array(plan.activities.sorted { $0.date < $1.date }.prefix(activityBudget))
        return plan
    }

    /// A UUID that is always the same for the same delivery, as AlarmKit needs UUIDs.
    static func uuid(for key: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    // MARK: Notifications

    private func reconcileNotifications(_ wanted: [PlannedNotification], agenda: Agenda) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let wantedIDs = Set(wanted.map(\.id))
        let stalePending = pending.subtracting(wantedIDs)
        center.removePendingNotificationRequests(withIdentifiers: Array(stalePending))
        var added = 0
        for notification in wanted where !pending.contains(notification.id) {
            if (try? await center.add(request(for: notification))) != nil { added += 1 }
        }
        let total = await center.pendingNotificationRequests().count
        log.info("Notifications: added \(added), removed \(stalePending.count), now \(total) pending")

        // Clear delivered reminders for tasks that are done, deleted or moved, and keep only the
        // latest repeat of each reminder.
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        var stale: [String] = []
        var newestRepeat: [String: (index: Int, id: String)] = [:]
        for id in delivered {
            guard let parts = DeliveryID(id) else { continue }
            let open = agenda.tasks[parts.task].map { !$0.isArchived } ?? false
            let current = agenda.reminderTimes(for: parts.task, at: Context()).contains {
                $0.key == parts.reminderKey && Int($0.date.timeIntervalSince1970) == parts.stamp
            }
            if !open || !current {
                stale.append(id)
            } else if let newest = newestRepeat[parts.base] {
                if parts.index > newest.index {
                    stale.append(newest.id)
                    newestRepeat[parts.base] = (parts.index, id)
                } else {
                    stale.append(id)
                }
            } else {
                newestRepeat[parts.base] = (parts.index, id)
            }
        }
        center.removeDeliveredNotifications(withIdentifiers: stale)
    }

    private func request(for notification: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = Self.category
        content.threadIdentifier = notification.task.uuidString
        content.userInfo = ["task": notification.task.uuidString]
        content.interruptionLevel = notification.sticky ? .timeSensitive : .active
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notification.date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        return UNNotificationRequest(identifier: notification.id, content: content, trigger: trigger)
    }

    /// The parts of a notification ID: "task/reminder/occurrence@stamp#repeat".
    struct DeliveryID {
        var task: TaskID
        var reminderKey: String
        var stamp: Int
        var index: Int
        var base: String

        init?(_ id: String) {
            let hash = id.split(separator: "#")
            let at = hash.first?.split(separator: "@") ?? []
            guard hash.count == 2, at.count == 2, let stamp = Int(at[1]), let index = Int(hash[1]),
                  let task = at[0].split(separator: "/").first.flatMap({ UUID(uuidString: String($0)) }) else { return nil }
            self.task = task
            self.reminderKey = String(at[0])
            self.stamp = stamp
            self.index = index
            self.base = String(hash[0])
        }
    }

    // MARK: Alarms (AlarmKit)

    private func reconcileAlarms(_ wanted: [PlannedAlarm]) async {
        let manager = AlarmManager.shared
        guard manager.authorizationState == .authorized else { return }
        let existing = Set(((try? manager.alarms) ?? []).map(\.id))
        let wantedIDs = Set(wanted.map(\.id))
        for id in existing.subtracting(wantedIDs) {
            try? manager.cancel(id: id)
        }
        for alarm in wanted where !existing.contains(alarm.id) {
            let configuration = AlarmManager.AlarmConfiguration<TaskAlarmMetadata>.alarm(
                schedule: .fixed(alarm.date),
                attributes: AlarmAttributes(
                    presentation: AlarmPresentation(alert: Self.alert(title: alarm.title)),
                    metadata: TaskAlarmMetadata(taskID: alarm.task),
                    tintColor: .orange
                ),
                secondaryIntent: CompleteTaskIntent(task: TaskEntity(id: alarm.task, title: alarm.title))
            )
            _ = try? await manager.schedule(id: alarm.id, configuration: configuration)
        }
    }

    /// The ringing alarm's Done button completes the task (R7).
    private static func alert(title: String) -> AlarmPresentation.Alert {
        let done = AlarmButton(text: "Done", textColor: .white, systemImageName: "checkmark")
        if #available(iOS 26.1, *) {
            return AlarmPresentation.Alert(title: "\(title)", secondaryButton: done, secondaryButtonBehavior: .custom)
        }
        let stop = AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.circle")
        return AlarmPresentation.Alert(title: "\(title)", stopButton: stop, secondaryButton: done, secondaryButtonBehavior: .custom)
    }

    // MARK: Live Activities

    private func reconcileActivities(_ wanted: [PlannedActivity]) async {
        let wantedKeys = Set(wanted.map(\.key))
        let current = Activity<TaskActivityAttributes>.activities
        for activity in current {
            let task = SharedStore.shared.agenda.tasks[activity.attributes.taskID]
            let stillOpen = task.map { !$0.isArchived } ?? false
            // A sticky reminder that has started stays until the task is done or moved.
            let started = activity.content.state.due <= .now
            if !stillOpen || (!started && !wantedKeys.contains(activity.attributes.key))
                || (started && !Self.isCurrent(activity.attributes.key)) {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let existing = Set(Activity<TaskActivityAttributes>.activities.map(\.attributes.key))
        for planned in wanted where !existing.contains(planned.key) {
            let attributes = TaskActivityAttributes(key: planned.key, taskID: planned.task, title: planned.title)
            let content = ActivityContent(state: TaskActivityAttributes.ContentState(due: planned.date), staleDate: nil)
            let alert = AlertConfiguration(title: "\(planned.title)", body: "Reminder", sound: .default)
            _ = try? Activity.request(
                attributes: attributes, content: content, pushType: nil, style: .standard,
                alertConfiguration: alert, start: planned.date
            )
        }
    }

    /// Whether a delivery key still matches the task's reminder time.
    private static func isCurrent(_ key: String) -> Bool {
        let at = key.split(separator: "@")
        guard at.count == 2, let stamp = Int(at[1]),
              let task = at[0].split(separator: "/").first.flatMap({ UUID(uuidString: String($0)) }) else { return false }
        return SharedStore.shared.agenda.reminderTimes(for: task, at: Context()).contains {
            $0.key == String(at[0]) && Int($0.date.timeIntervalSince1970) == stamp
        }
    }
}
