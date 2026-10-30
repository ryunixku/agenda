#if DEBUG
import AgendaCore
import AgendaData
import Foundation

/// Sample data for trying the app in the Simulator. Debug builds only: launch with `-demo` on an
/// empty store, for example `xcrun simctl launch booted com.example.agenda -demo`.
enum DemoData {
    static func seedIfRequested(_ store: AgendaStore) {
        guard ProcessInfo.processInfo.arguments.contains("-demo"), store.agenda.tasks.isEmpty else { return }
        let context = Context()
        let today = context.today
        TaskActions.attempt {
            try store.perform { agenda throws(RuleViolation) in
                let home = agenda.addList("Home")
                let groceries = agenda.addList("Groceries")
                let move = agenda.addProject("Move flat")

                let bank = try agenda.addTask("Call the bank", in: home, plan: Plan(start: Moment(today, TimeOfDay(10))), at: context)
                try agenda.addReminder(.sticky, .minutes(-15), to: bank)
                let tax = try agenda.addTask("Pay council tax", in: home, plan: Plan(deadline: Moment(today.adding(days: -2))), at: context)
                try agenda.addNote("Reference number is on the letter.", to: .task(tax), at: context)
                let bins = try agenda.addTask(
                    "Bins out", in: home,
                    plan: Plan(start: Moment(today, TimeOfDay(20)), recurrence: Recurrence(.weekly)), at: context
                )
                try agenda.addReminder(.alarm, .minutes(0), to: bins)
                try agenda.addTask("Milk", in: groceries, at: context)
                try agenda.addTask("Coffee beans", in: groceries, at: context)

                let quote = try agenda.addTask(
                    "Get a removals quote", in: move,
                    plan: Plan(start: Moment(today.adding(days: 1)), deadline: Moment(today.adding(days: 3))), at: context
                )
                let book = try agenda.addTask("Book the van", in: move, plan: Plan(start: Moment(today.adding(days: 4))), at: context)
                try agenda.link(quote, then: book)
                let pack = try agenda.addTask("Pack", in: move, plan: Plan(start: Moment(today.adding(days: 6))), at: context)
                for room in ["Kitchen", "Bedroom", "Books"] {
                    try agenda.addSubtask(room, to: pack, at: context)
                }
                try agenda.addNote("New address: 12 Rose Street", to: .container(move), at: context)

                let old = try agenda.addTask("Renew passport", in: home, at: context)
                try agenda.complete(old, at: context)
                try agenda.addTask("Look into solar panels", at: context)
            }
        }
    }
}
#endif
