import AgendaCore
import AgendaData
import BackgroundTasks
import SwiftUI

@main
struct AgendaApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let store = SharedStore.shared
    private let router = Router.shared

    init() {
        #if DEBUG
        DemoData.seedIfRequested(store)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .onOpenURL { router.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Pick up what iCloud, widgets or the share extension changed meanwhile.
                store.reload()
                router.checkCaptureRequest()
                Task { await ReminderEngine.shared.reconcile(store.agenda) }
            case .background:
                AppDelegate.scheduleRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppDelegate.refreshTaskID)) {
            // Tops up the reminders iOS holds, since it keeps only the nearest 64.
            await AppDelegate.refreshInBackground()
        }
    }
}
