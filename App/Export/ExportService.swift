import CoreTransferable
import EmberKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Flameshot's output actions: copy (default "accept"), save, share.
@MainActor
enum ExportService {
    static func pngData(of document: EditorDocument) -> Data? {
        document.flattenedImage().flatMap(ImageEncoding.png)
    }

    /// Puts PNG data on the pasteboard so the exact pixels survive (a
    /// `UIImage` would be re-encoded and lose its scale).
    @discardableResult
    static func copy(_ document: EditorDocument) -> Bool {
        guard let data = pngData(of: document) else { return false }
        UIPasteboard.general.setData(data, forPasteboardType: UTType.png.identifier)
        return true
    }

    static func saveToPhotos(_ document: EditorDocument) async throws {
        guard let data = pngData(of: document) else { throw CocoaError(.fileWriteUnknown) }
        try await PhotoLibraryService.save(pngData: data)
    }

    /// Flameshot's default name pattern `%F_%H-%M`.
    static func defaultFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: date)
    }
}

/// Rendered lazily when the share sheet asks for it.
struct RenderedCapture: Transferable {
    let render: @MainActor () -> Data?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { capture in
            guard let data = await capture.render() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName("Ember.png")
    }
}

/// For "Save to Files…" via `.fileExporter`.
struct PNGFile: FileDocument {
    static var readableContentTypes: [UTType] { [.png] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
