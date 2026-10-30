import AgendaCore
import AgendaData
import Foundation

/// The in-app versions of the common actions, which also say what happened.
enum TaskActions {
    static func attempt(_ router: Router = .shared, _ body: () throws -> Void) {
        do {
            try body()
        } catch let violation as RuleViolation {
            router.show(violation)
        } catch {
            router.error = error.localizedDescription
        }
    }

    /// Marks a task done. If open subtasks were archived with it as not done, offers to mark them
    /// done instead (S3, S10).
    static func complete(_ id: TaskID, store: AgendaStore, router: Router = .shared) {
        let open = store.agenda.subtasks(of: id).filter { !$0.isArchived }.count
        attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.complete(id, at: Context()) }
        }
        guard open > 0, store.agenda.tasks[id]?.isArchived == true else { return }
        router.showBanner(
            "\(open) open \(open == 1 ? "subtask" : "subtasks") archived as not done",
            actionTitle: "Mark all done"
        ) {
            attempt(router) { try store.perform { agenda throws(RuleViolation) in try agenda.markSubtasksDone(of: id) } }
        }
    }

    /// Finishes a project. Open tasks are archived as not done, with an offer to mark them done (C3, C6).
    static func finish(project id: ContainerID, store: AgendaStore, router: Router = .shared) {
        let open = store.agenda.tasks.values.filter { $0.container == id && !$0.isArchived }.count
        attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.completeProject(id, at: Context()) }
        }
        guard store.agenda.containers[id]?.archived != nil else { return }
        guard open > 0 else {
            router.showBanner("Project finished")
            return
        }
        router.showBanner(
            "Project finished. \(open) open \(open == 1 ? "task" : "tasks") archived as not done",
            actionTitle: "Mark all done"
        ) {
            attempt(router) { try store.perform { agenda throws(RuleViolation) in try agenda.markLeftoversDone(inProject: id) } }
        }
    }

    static func reschedule(_ id: TaskID, to preset: ReschedulePreset, store: AgendaStore, router: Router = .shared) {
        attempt(router) {
            try store.perform { agenda throws(RuleViolation) in try agenda.reschedule(id, to: preset, at: Context()) }
        }
        if let moved = (try? store.agenda.schedule(of: id, at: Context()))?.doDate {
            router.showBanner("Moved to \(Format.moment(moved))")
        }
    }

    static func clone(_ id: TaskID, store: AgendaStore, router: Router = .shared) {
        attempt(router) {
            let copy = try store.clone(id)
            router.open(copy)
        }
    }

    static func delete(_ id: TaskID, store: AgendaStore, router: Router = .shared) {
        attempt(router) { try store.delete(id) }
    }
}
