import AgendaCore
import AgendaData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// "Add to Agenda" in any app's share sheet. Whatever is shared becomes a task in the Inbox (B2),
/// then the sheet closes by itself.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let host = UIHostingController(rootView: ShareView(items: items) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

struct ShareView: View {
    let items: [NSExtensionItem]
    let finish: () -> Void
    @State private var added: [String] = []
    @State private var working = true

    var body: some View {
        VStack(spacing: 12) {
            if working {
                ProgressView()
            } else {
                Image(systemName: added.isEmpty ? "xmark.circle" : "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(added.isEmpty ? .secondary : Color.green)
                Text(added.isEmpty ? "Nothing to add" : "Added to your Inbox")
                    .font(.headline)
                ForEach(added, id: \.self) { title in
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(28)
        .frame(maxWidth: 320)
        .background(.regularMaterial, in: .rect(cornerRadius: 24))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await addAll()
            working = false
            try? await Task.sleep(for: .seconds(1.2))
            finish()
        }
    }

    private func addAll() async {
        let store = SharedStore.shared
        store.reload()
        for item in items {
            let pageTitle = item.attributedContentText?.string
            for provider in item.attachments ?? [] {
                guard let shared = await Self.shared(from: provider, pageTitle: pageTitle) else { continue }
                do throws(RuleViolation) {
                    let id: TaskID
                    switch shared {
                    case .text(let text):
                        id = try store.perform { agenda throws(RuleViolation) in try agenda.addTask(text, at: Context()) }
                    case .content(let content):
                        id = try store.capture(content)
                    }
                    added.append(store.agenda.tasks[id]?.title ?? "")
                } catch {}
            }
        }
    }

    enum Shared {
        case text(String)
        case content(CapturedContent)
    }

    /// Plain text becomes a task's title; a web page, image or file becomes the task itself.
    private static func shared(from provider: NSItemProvider, pageTitle: String?) async -> Shared? {
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
           !provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true {
                return .content(CapturedContent(kind: .link, url: url, text: pageTitle))
            }
            return trimmed.isEmpty ? nil : .text(String(trimmed.prefix(200)))
        }
        return await content(from: provider, pageTitle: pageTitle).map(Shared.content)
    }

    private static func content(from provider: NSItemProvider, pageTitle: String?) async -> CapturedContent? {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
            if url.isFileURL {
                guard let data = try? Data(contentsOf: url) else { return nil }
                return CapturedContent(kind: kind(for: url), data: data, filename: url.lastPathComponent, typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier)
            }
            return CapturedContent(kind: .link, url: url, text: pageTitle)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
            let data: Data? = (item as? Data)
                ?? (item as? UIImage)?.jpegData(compressionQuality: 0.8)
                ?? (item as? URL).flatMap { try? Data(contentsOf: $0) }
            guard let data else { return nil }
            return CapturedContent(kind: .photo, data: data, filename: "Photo.jpg", typeIdentifier: UTType.jpeg.identifier)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier),
           let url = try? await provider.loadItem(forTypeIdentifier: UTType.item.identifier) as? URL,
           let data = try? Data(contentsOf: url) {
            return CapturedContent(kind: kind(for: url), data: data, filename: url.lastPathComponent, typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier)
        }
        return nil
    }

    private static func kind(for url: URL) -> BlobRef.Kind {
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .image) == true { return .photo }
        if type?.conforms(to: .audio) == true { return .voice }
        return .file
    }
}
