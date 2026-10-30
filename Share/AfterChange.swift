import AgendaCore
import WidgetKit

extension SharedStore {
    /// The app updates reminders the next time it opens; new tasks from sharing have none yet.
    static func afterChange(_ agenda: Agenda) {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
