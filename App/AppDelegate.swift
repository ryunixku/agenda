import AgendaCore
import BackgroundTasks
import CoreData
import UIKit
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static let refreshTaskID = (Bundle.main.bundleIdentifier ?? "agenda") + ".refresh"

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(ReminderEngine.categories)
        // iCloud brought changes from another device.
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            Task { @MainActor in
                SharedStore.shared.reload()
                await ReminderEngine.shared.reconcile(SharedStore.shared.agenda)
            }
        }
        return true
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated static func refreshInBackground() async {
        await MainActor.run { scheduleRefresh() }
        await MainActor.run { SharedStore.shared.reload() }
        let agenda = await MainActor.run { SharedStore.shared.agenda }
        await ReminderEngine.shared.reconcile(agenda)
    }

    // MARK: Notification buttons (ARCHITECTURE §4.3)

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        guard let id = (response.notification.request.content.userInfo["task"] as? String).flatMap(UUID.init(uuidString:)) else { return }
        await MainActor.run {
            let router = Router.shared
            switch ReminderEngine.Action(rawValue: action) {
            case .done:
                do throws(RuleViolation) { try AgendaActions.complete(id) } catch { router.show(error) }
            case .tonight:
                do throws(RuleViolation) { try AgendaActions.reschedule(id, to: .tonight) } catch { router.show(error) }
            case .tomorrow:
                do throws(RuleViolation) { try AgendaActions.reschedule(id, to: .tomorrow) } catch { router.show(error) }
            case .pick:
                router.rescheduling = TaskRef(id: id)
            case nil:
                router.open(id)
            }
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
