import AgendaCore
import AgendaData
import SwiftUI

/// One field that is always ready (ARCHITECTURE §3.6). Type and press return to add a task; the
/// paperclip captures a photo, scan, voice memo, file or link as a task of its own (B2).
struct CaptureBar: View {
    var container: ContainerID?
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .foregroundStyle(.secondary)
            TextField("Add a task", text: $text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
            CaptureMenu { content in
                capture(content)
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .accessibilityLabel("Capture")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: .capsule)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .onChange(of: router.captureRequested, initial: true) { _, requested in
            if requested {
                focused = true
                router.captureRequested = false
            }
        }
    }

    private func add() {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        TaskActions.attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.addTask(title, in: container, at: Context()) }
        }
        text = ""
        focused = true
    }

    private func capture(_ content: CapturedContent) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        TaskActions.attempt(router) {
            let id = try store.capture(content, title: title, in: container)
            router.showBanner("Added “\(store.agenda.tasks[id]?.title ?? "")”", actionTitle: "Open") {
                router.open(id)
            }
        }
        text = ""
    }
}
