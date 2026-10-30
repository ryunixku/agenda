import AgendaCore
import SwiftUI

@main
struct AgendaApp: App {
    var body: some Scene {
        WindowGroup {
            NowPlaceholderView()
        }
    }
}

/// Stands in for the Now screen until the real screens arrive (M4). It already asks the core
/// what can be done now, so it proves the app is wired to `AgendaCore`.
struct NowPlaceholderView: View {
    private let agenda = Agenda()

    var body: some View {
        NavigationStack {
            let tasks = agenda.actionable(at: Context())
            Group {
                if tasks.isEmpty {
                    ContentUnavailableView(
                        "Nothing to do now",
                        systemImage: "checkmark.circle",
                        description: Text("Tasks for today show up here.")
                    )
                } else {
                    List(tasks) { Text($0.title) }
                }
            }
            .navigationTitle("Now")
        }
    }
}
