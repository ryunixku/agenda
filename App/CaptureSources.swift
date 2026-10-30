import AgendaCore
import AgendaData
import AVFoundation
import LinkPresentation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import Vision
import VisionKit

/// A menu of everything that can be captured: photo, camera, scan, voice memo, file and link
/// (B1). Each source hands back `CapturedContent`, with text found in it where possible so the
/// task gets a useful title without typing (B2).
struct CaptureMenu<Label: View>: View {
    let onCapture: (CapturedContent) -> Void
    @ViewBuilder let label: () -> Label

    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showScanner = false
    @State private var showRecorder = false
    @State private var showFiles = false
    @State private var showLink = false
    @State private var link = ""

    var body: some View {
        Menu {
            Button("Photo Library", systemImage: "photo.on.rectangle") { showPhotos = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera", systemImage: "camera") { showCamera = true }
            }
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Document", systemImage: "doc.viewfinder") { showScanner = true }
            }
            Button("Voice Memo", systemImage: "mic") { showRecorder = true }
            Button("File", systemImage: "doc") { showFiles = true }
            Button("Link", systemImage: "link") {
                link = ""
                showLink = true
            }
        } label: {
            label()
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self) else { return }
                let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.8) ?? data
                let text = await TextFinder.text(in: jpeg)
                onCapture(CapturedContent(kind: .photo, data: jpeg, filename: "Photo.jpg", typeIdentifier: UTType.jpeg.identifier, text: text))
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                Task {
                    let jpeg = image.jpegData(compressionQuality: 0.8)
                    let text = await jpeg.asyncMap(TextFinder.text(in:)) ?? nil
                    onCapture(CapturedContent(kind: .photo, data: jpeg, filename: "Photo.jpg", typeIdentifier: UTType.jpeg.identifier, text: text))
                }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScanner { pdf, firstPage in
                Task {
                    let text = await firstPage.asyncMap(TextFinder.text(in:)) ?? nil
                    onCapture(CapturedContent(kind: .scan, data: pdf, filename: "Scan.pdf", typeIdentifier: UTType.pdf.identifier, text: text))
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showRecorder) {
            VoiceRecorderView { data in
                onCapture(CapturedContent(kind: .voice, data: data, filename: "Voice memo.m4a", typeIdentifier: UTType.mpeg4Audio.identifier))
            }
            .presentationDetents([.height(280)])
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            onCapture(CapturedContent(
                kind: .file, data: data, filename: url.lastPathComponent,
                typeIdentifier: UTType(filenameExtension: url.pathExtension)?.identifier
            ))
        }
        .alert("Add a link", isPresented: $showLink) {
            TextField("https://", text: $link)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
            Button("Add") {
                let text = link.trimmingCharacters(in: .whitespaces)
                guard let url = URL(string: text.contains("://") ? text : "https://\(text)"), url.host() != nil else { return }
                Task {
                    let title = await TextFinder.title(of: url)
                    onCapture(CapturedContent(kind: .link, url: url, text: title))
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async -> T) async -> T? {
        guard let self else { return nil }
        return await transform(self)
    }
}

/// Finds text in captured content, to suggest a title.
enum TextFinder {
    /// The words in an image, line by line (Vision text recognition).
    static func text(in imageData: Data) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            guard let image = UIImage(data: imageData)?.cgImage else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            try? VNImageRequestHandler(cgImage: image).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }.value
    }

    /// A web page's title.
    static func title(of url: URL) async -> String? {
        let provider = LPMetadataProvider()
        provider.timeout = 6
        return try? await provider.startFetchingMetadata(for: url).title
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: UIViewControllerRepresentableContext<CameraPicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: UIViewControllerRepresentableContext<CameraPicker>) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// The system document scanner. Hands back every page as one PDF, plus the first page as an
/// image for finding text.
struct DocumentScanner: UIViewControllerRepresentable {
    let onScan: (Data, Data?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: UIViewControllerRepresentableContext<DocumentScanner>) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: UIViewControllerRepresentableContext<DocumentScanner>) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner

        init(parent: DocumentScanner) {
            self.parent = parent
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            let bounds = CGRect(origin: .zero, size: pages.first?.size ?? CGSize(width: 612, height: 792))
            let pdf = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
                for page in pages {
                    let rect = CGRect(origin: .zero, size: page.size)
                    context.beginPage(withBounds: rect, pageInfo: [:])
                    page.draw(in: rect)
                }
            }
            parent.onScan(pdf, pages.first?.jpegData(compressionQuality: 0.8))
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.dismiss()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.dismiss()
        }
    }
}

struct VoiceRecorderView: View {
    let onSave: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var recorder: AVAudioRecorder?
    @State private var started: Date?
    @State private var denied = false

    private var url: URL {
        FileManager.default.temporaryDirectory.appending(path: "voice-memo.m4a")
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("Voice memo")
                .font(.headline)
            Group {
                if let started {
                    Text(started, style: .timer)
                } else {
                    Text("0:00")
                }
            }
            .font(.largeTitle.monospacedDigit())
            Button {
                Task { await toggle() }
            } label: {
                Image(systemName: recorder == nil ? "record.circle" : "stop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
            }
            .accessibilityLabel(recorder == nil ? "Record" : "Stop and save")
            if denied {
                Text("Allow the microphone in Settings to record.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onDisappear { recorder?.stop() }
    }

    private func toggle() async {
        if let recorder {
            recorder.stop()
            self.recorder = nil
            try? AVAudioSession.sharedInstance().setActive(false)
            if let data = try? Data(contentsOf: url) {
                onSave(data)
            }
            dismiss()
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            denied = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
        ]
        guard let recorder = try? AVAudioRecorder(url: url, settings: settings), recorder.record() else { return }
        self.recorder = recorder
        started = .now
    }
}
