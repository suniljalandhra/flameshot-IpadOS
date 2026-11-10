import EmberKit
import Photos
import PhotosUI
import SwiftUI

/// Capture sources. iPadOS doesn't let an app grab the screen on a hotkey the
/// way Flameshot does on a desktop, so Ember offers the closest equivalents.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    @Environment(\.scenePhase) private var scenePhase

    @State private var latest: PhotoLibraryService.LatestScreenshot?
    @State private var photoAccess = PhotoLibraryService.readStatus
    @State private var pickerItem: PhotosPickerItem?
    @State private var frames: [BroadcastFrame] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    latestScreenshotCard
                    otherSources
                    broadcastSection
                    tips
                }
                .padding(32)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Ember")
            .overlay {
                if isLoading {
                    ProgressView().controlSize(.large)
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await open(item) }
        }
        .alert("Couldn't open image", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var latestScreenshotCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Latest screenshot").font(.title2.bold())
            Text("Take a screenshot anywhere (top button + volume up, or swipe up from a bottom corner with Apple Pencil), then come back here to annotate it.")
                .foregroundStyle(.secondary)

            switch photoAccess {
            case .authorized, .limited:
                if let latest {
                    Button {
                        Task { await openLatest(latest) }
                    } label: {
                        HStack(spacing: 20) {
                            if let thumb = latest.thumbnail {
                                Image(uiImage: thumb)
                                    .resizable().scaledToFit()
                                    .frame(maxWidth: 320, maxHeight: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(radius: 4, y: 2)
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                Label("Annotate", systemImage: "pencil.tip.crop.circle")
                                    .font(.headline)
                                if let date = latest.creationDate {
                                    Text(date, format: .relative(presentation: .named))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("No screenshots found yet.").foregroundStyle(.secondary)
                }
            case .notDetermined:
                Button("Allow access to screenshots") {
                    Task {
                        _ = await PhotoLibraryService.requestReadAccess()
                        await refresh()
                    }
                }
                .buttonStyle(.borderedProminent)
            default:
                Text("Photo access is off. Turn it on in Settings › Privacy & Security › Photos › Ember, or use the photo picker below.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var otherSources: some View {
        HStack(spacing: 16) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                SourceTile(title: "Choose Photo", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.plain)

            Button(action: pasteImage) {
                SourceTile(title: "Paste Image", systemImage: "doc.on.clipboard")
            }
            .buttonStyle(.plain)
            .keyboardShortcut("v", modifiers: .command)
        }
    }

    private var broadcastSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Live screen capture").font(.title2.bold())
            Text("Start a screen broadcast with ReplayKit, switch to any app, then come back. Ember keeps the last \(BroadcastCapture.store?.capacity ?? 10) frames (two per second). Pick one to annotate.")
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                BroadcastPickerButton()
                    .frame(width: 56, height: 56)
                    .background(Color.emberPurple, in: Circle())
                    .foregroundStyle(.white)
                Text("Start or stop broadcast").font(.headline)
                Spacer()
                Button {
                    frames = BroadcastCapture.frames()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            if frames.isEmpty {
                Text("No frames yet.").foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(frames) { frame in
                            Button { openFrame(frame) } label: {
                                FrameThumbnail(frame: frame)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("In the editor").font(.headline)
            Text("Drag to select an area, or tap to use the whole image. Draw with Apple Pencil or your finger. Long-press or squeeze Apple Pencil Pro to open the colour wheel. Double-tap Apple Pencil to switch back to the previous tool. With a keyboard you can use Flameshot's keys: P, D, A, S, R, C, M, T, B, I; ⌘Z, ⌘C, ⌘S; Return to copy and close; Esc to close; Space for the side panel.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func refresh() async {
        photoAccess = PhotoLibraryService.readStatus
        latest = await PhotoLibraryService.latestScreenshot(thumbnailSize: CGSize(width: 640, height: 480))
        frames = BroadcastCapture.frames()
    }

    private func openLatest(_ shot: PhotoLibraryService.LatestScreenshot) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let image = try await PhotoLibraryService.fullImage(assetID: shot.assetID)
            model.openEditor(with: image, pixelScale: displayScale)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func open(_ item: PhotosPickerItem) async {
        isLoading = true
        defer {
            isLoading = false
            pickerItem = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = ImageEncoding.decode(data)
            else { throw PhotoLibraryService.Failure.unreadable }
            model.openEditor(with: image, pixelScale: displayScale)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pasteImage() {
        guard let image = UIPasteboard.general.image?.normalizedCGImage else {
            errorMessage = "There's no image on the clipboard."
            return
        }
        model.openEditor(with: image, pixelScale: displayScale)
    }

    private func openFrame(_ frame: BroadcastFrame) {
        guard let image = BroadcastCapture.image(for: frame) else {
            errorMessage = PhotoLibraryService.Failure.unreadable.localizedDescription
            return
        }
        model.openEditor(with: image, pixelScale: displayScale)
    }
}

private struct SourceTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage).font(.system(size: 28))
            Text(title).font(.headline)
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .hoverEffect(.lift)
    }
}

private struct FrameThumbnail: View {
    let frame: BroadcastFrame
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 200, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(frame.date, format: .dateTime.hour().minute().second())
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .task(id: frame.id) {
            image = BroadcastCapture.thumbnail(for: frame)
        }
    }
}
