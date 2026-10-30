import Foundation
import SwiftData

// SwiftData records, kept simple for CloudKit (ARCHITECTURE §3.5): every attribute has a default,
// nothing is unique and there are no relationships. Each record holds one core value encoded as
// JSON, so the rules stay in AgendaCore and storage only saves and loads.

@Model
final class TaskRecord {
    var id: UUID = UUID()
    var payload: Data = Data()
    var modifiedAt: Date = Date.distantPast

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
        self.modifiedAt = .now
    }
}

@Model
final class ContainerRecord {
    var id: UUID = UUID()
    var payload: Data = Data()
    var modifiedAt: Date = Date.distantPast

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
        self.modifiedAt = .now
    }
}

@Model
final class CompletionRecord {
    var id: UUID = UUID()
    var payload: Data = Data()

    init(id: UUID, payload: Data) {
        self.id = id
        self.payload = payload
    }
}

/// The bytes and details of a blob. The core only knows which task owns it.
@Model
final class BlobRecord {
    var id: UUID = UUID()
    var kind: String = "file"
    @Attribute(.externalStorage) var data: Data?
    var filename: String?
    var typeIdentifier: String?
    var url: String?
    /// Text found in the content: a scan's words, a page title.
    var text: String?

    init(id: UUID, content: CapturedContent) {
        self.id = id
        self.kind = content.kind.rawValue
        self.data = content.data
        self.filename = content.filename
        self.typeIdentifier = content.typeIdentifier
        self.url = content.url?.absoluteString
        self.text = content.text
    }
}
