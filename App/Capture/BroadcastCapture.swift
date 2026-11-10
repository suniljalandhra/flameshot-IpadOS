import EmberKit
import ReplayKit
import SwiftUI

/// ReplayKit's system broadcast button, pre-selecting Ember's Broadcast Upload
/// Extension. Tapping it shows the system sheet to start / stop recording the
/// **whole screen** (other apps included). Ember's extension keeps the most
/// recent frames in the App Group; see `BroadcastFrameStore`.
struct BroadcastPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        picker.preferredExtension = BroadcastCapture.extensionBundleID
        picker.showsMicrophoneButton = false
        // The system button's record glyph uses the tint colour; make it
        // white on the purple circle.
        for case let button as UIButton in picker.subviews {
            button.tintColor = .white
            button.imageView?.tintColor = .white
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

enum BroadcastCapture {
    /// The extension's bundle ID is the app's plus `.Broadcast` (see project.yml).
    static var extensionBundleID: String? {
        Bundle.main.bundleIdentifier.map { $0 + ".Broadcast" }
    }

    static let store = BroadcastFrameStore.appGroup()

    static func frames() -> [BroadcastFrame] {
        store?.frames() ?? []
    }

    static func image(for frame: BroadcastFrame) -> CGImage? {
        guard let data = try? Data(contentsOf: frame.url) else { return nil }
        return ImageEncoding.decode(data)
    }

    static func thumbnail(for frame: BroadcastFrame) -> UIImage? {
        ImageEncoding.thumbnail(at: frame.url, maxPixelSize: 480).map { UIImage(cgImage: $0) }
    }
}
