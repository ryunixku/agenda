import ActivityKit
import AlarmKit
import Foundation

/// A sticky reminder on the Lock Screen and in the Dynamic Island (R6).
nonisolated struct TaskActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var due: Date
    }

    /// The reminder delivery this activity stands for, so the engine can match it up.
    var key: String
    var taskID: UUID
    var title: String
}

/// What an alarm needs to know about its task, for the Done button (R7).
nonisolated struct TaskAlarmMetadata: AlarmMetadata {
    var taskID: UUID
}
