import AgendaCore
import Foundation
import Observation

struct TaskRef: Identifiable, Hashable {
    let id: TaskID
}

/// Where the app is: the tab, the open task, and messages to show.
@Observable
final class Router {
    static let shared = Router()

    enum Tab: Hashable {
        case now, lists, calendar, archive
    }

    struct Banner: Identifiable {
        let id = UUID()
        var message: String
        var actionTitle: String?
        var action: (() -> Void)?
    }

    var tab: Tab = .now
    var openTask: TaskRef?
    var rescheduling: TaskRef?
    /// Set to put the cursor in the capture field.
    var captureRequested = false
    var banner: Banner?
    var error: String?

    func open(_ id: TaskID) {
        openTask = TaskRef(id: id)
    }

    func show(_ violation: RuleViolation) {
        error = violation.message
    }

    func showBanner(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        banner = Banner(message: message, actionTitle: actionTitle, action: action)
    }

    /// Control Center, the Action button and Siri ask for capture through the App Group.
    func checkCaptureRequest() {
        let defaults = UserDefaults(suiteName: Bundle.main.infoDictionary?["AgendaAppGroup"] as? String)
        if defaults?.bool(forKey: OpenCaptureIntent.requestKey) == true {
            defaults?.set(false, forKey: OpenCaptureIntent.requestKey)
            requestCapture()
        }
    }

    func requestCapture() {
        openTask = nil
        tab = .now
        captureRequested = true
    }

    /// agenda://task/<id> opens a task; agenda://capture opens capture.
    func handle(_ url: URL) {
        guard url.scheme == "agenda" else { return }
        switch url.host() {
        case "task":
            if let id = UUID(uuidString: url.lastPathComponent) { open(id) }
        case "capture":
            requestCapture()
        default:
            break
        }
    }
}
