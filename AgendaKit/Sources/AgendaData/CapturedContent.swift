import AgendaCore
import Foundation

/// Something the user captured: a photo, scan, file, voice memo or link (B1).
public struct CapturedContent: Hashable, Sendable {
    public var kind: BlobRef.Kind
    public var data: Data?
    public var filename: String?
    public var typeIdentifier: String?
    public var url: URL?
    /// Text found in the content, such as a scan's words or a page title.
    public var text: String?

    public init(
        kind: BlobRef.Kind,
        data: Data? = nil,
        filename: String? = nil,
        typeIdentifier: String? = nil,
        url: URL? = nil,
        text: String? = nil
    ) {
        self.kind = kind
        self.data = data
        self.filename = filename
        self.typeIdentifier = typeIdentifier
        self.url = url
        self.text = text
    }

    /// A title for a task that is this content (B2), so capturing needs no typing.
    public var suggestedTitle: String {
        if let line = text?.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces),
           !line.isEmpty {
            return String(line.prefix(80))
        }
        switch kind {
        case .photo: return "Photo"
        case .scan: return "Scanned document"
        case .voice: return "Voice memo"
        case .file: return filename.map { ($0 as NSString).deletingPathExtension } ?? "File"
        case .link: return url?.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? "Link"
        }
    }
}
