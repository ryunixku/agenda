import AgendaCore
import WidgetKit

extension SharedStore {
    /// After any change: bring reminders up to date and refresh the widgets.
    static func afterChange(_ agenda: Agenda) {
        Task { await ReminderEngine.shared.reconcile(agenda) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
