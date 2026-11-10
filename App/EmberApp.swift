import EmberKit
import SwiftUI

@main
struct EmberApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(.emberPurple)
        }
    }
}

/// Home (capture sources) or the editor, full screen, like Flameshot's frozen
/// screen overlay.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            if let document = model.document {
                CaptureEditorView(document: document) { model.closeEditor() }
                    .transition(.opacity)
            } else {
                HomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.document == nil)
        // The editor shows a frozen screenshot that has its own status bar;
        // hide the live one so the two don't overlap (Flameshot covers the
        // whole screen too). Applied at the root so it reaches the window.
        .statusBarHidden(model.document != nil)
    }
}

/// App-level state: which capture is open, plus tool settings persisted
/// between sessions (Flameshot keeps them in its config file).
@MainActor
@Observable
final class AppModel {
    var document: EditorDocument?
    var errorMessage: String?

    private static let settingsKey = "ember.toolSettings"

    func openEditor(with image: CGImage, pixelScale: CGFloat) {
        document = EditorDocument(image: image, pixelScale: pixelScale, settings: loadSettings())
    }

    func closeEditor() {
        if let document { saveSettings(document.settings) }
        document = nil
    }

    private func loadSettings() -> ToolSettings {
        guard let data = UserDefaults.standard.data(forKey: Self.settingsKey),
              let settings = try? JSONDecoder().decode(ToolSettings.self, from: data)
        else { return ToolSettings() }
        return settings
    }

    private func saveSettings(_ settings: ToolSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.settingsKey)
        }
    }
}
