import AppIntents

/// What Siri, Spotlight and the Shortcuts app offer without any setup.
struct AgendaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddTaskIntent(),
            phrases: ["Add a task in \(.applicationName)", "Add to \(.applicationName)"],
            shortTitle: "Add Task",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: WhatsNextIntent(),
            phrases: ["What's next in \(.applicationName)", "What should I do in \(.applicationName)"],
            shortTitle: "What's Next",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: ["Capture in \(.applicationName)"],
            shortTitle: "Capture",
            systemImageName: "camera"
        )
    }
}
