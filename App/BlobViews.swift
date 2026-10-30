import AgendaCore
import AgendaData
import QuickLook
import SwiftUI

/// A task's attachments: tap to open (QuickLook for photos, scans, files and voice memos; the
/// browser for links).
struct AttachmentsSection: View {
    let task: TaskItem
    @Environment(AgendaStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.openURL) private var openURL
    @State private var preview: URL?

    var body: some View {
        Section("Attachments") {
            ForEach(task.blobs) { blob in
                let content = store.content(of: blob.id)
                Button {
                    open(blob, content)
                } label: {
                    BlobRow(blob: blob, content: content, isPrimary: task.primaryBlob == blob.id)
                }
                .foregroundStyle(.primary)
                .swipeActions {
                    if !task.isArchived {
                        Button("Remove", systemImage: "trash", role: .destructive) {
                            TaskActions.attempt(router) { try store.removeBlob(blob.id, from: task.id) }
                        }
                    }
                }
            }
            if !task.isArchived {
                CaptureMenu { content in
                    TaskActions.attempt(router) { try store.attach(content, to: task.id) }
                } label: {
                    Label("Add attachment", systemImage: "paperclip")
                }
            }
        }
        .quickLookPreview($preview)
    }

    private func open(_ blob: BlobRef, _ content: CapturedContent?) {
        guard let content else { return }
        if blob.kind == .link, let url = content.url {
            openURL(url)
            return
        }
        guard let data = content.data else { return }
        let name = content.filename ?? "\(blob.kind.rawValue)"
        let url = FileManager.default.temporaryDirectory.appending(path: blob.id.uuidString).appending(path: name)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url)
        preview = url
    }
}

struct BlobRow: View {
    let blob: BlobRef
    let content: CapturedContent?
    var isPrimary = false

    var body: some View {
        HStack(spacing: 12) {
            if blob.kind == .photo, let data = content?.data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(.rect(cornerRadius: 8))
            } else {
                Image(systemName: icon(for: blob.kind))
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(.fill.tertiary, in: .rect(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var name: String {
        if let text = content?.text?.split(whereSeparator: \.isNewline).first, blob.kind == .link {
            return String(text)
        }
        return content?.filename ?? content?.url?.host() ?? blob.kind.rawValue.capitalized
    }

    private var detail: String? {
        var parts: [String] = []
        if isPrimary { parts.append("This is the task") }
        if blob.kind == .link, let url = content?.url { parts.append(url.absoluteString) }
        if let data = content?.data { parts.append(data.count.formatted(.byteCount(style: .file))) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
