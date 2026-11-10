import EmberKit
import SwiftUI

/// Flameshot's side panel (Space): colour, size and per-tool options, plus
/// export actions that don't fit on the toolbar.
struct SidePanel: View {
    @Bindable var document: EditorDocument
    var onCopy: () -> Void
    var onSaveToPhotos: () -> Void
    var onSaveToFiles: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Form {
            Section {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(ToolKind.allCases) { tool in
                        let active = document.settings.tool == tool
                        Button {
                            document.selectTool(tool)
                        } label: {
                            Image(systemName: tool.systemImage)
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(active ? .white : .primary)
                                .background(active ? Color.emberPurple : Color.secondary.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tool.title)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Tool: \(document.settings.tool.title)")
            }

            Section("Colour") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 10) {
                    ForEach(Array(RGBAColor.defaultPalette.enumerated()), id: \.offset) { _, color in
                        Button {
                            document.settings.color = color
                        } label: {
                            Circle()
                                .fill(Color(color))
                                .overlay(Circle().strokeBorder(Color.primary.opacity(document.settings.color == color ? 0.9 : 0.15),
                                                               lineWidth: document.settings.color == color ? 3 : 1))
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
                ColorPicker("Custom colour", selection: Binding(
                    get: { Color(document.settings.color) },
                    set: { document.settings.color = RGBAColor($0) }
                ), supportsOpacity: false)
            }

            Section(document.settings.tool.usesFontSize ? "Font size" : "Thickness") {
                let range = document.settings.activeSizeRange
                Stepper(value: Binding(
                    get: { Double(document.settings.activeSize) },
                    set: { document.settings.activeSize = CGFloat($0) }
                ), in: Double(range.lowerBound)...Double(range.upperBound)) {
                    Text("\(Int(document.settings.activeSize)) pt").monospacedDigit()
                }
                Slider(value: Binding(
                    get: { Double(document.settings.activeSize) },
                    set: { document.settings.activeSize = CGFloat($0.rounded()) }
                ), in: Double(range.lowerBound)...Double(range.upperBound))
            }

            Section {
                Picker("Arrow style", selection: $document.settings.arrowStyle) {
                    ForEach(ArrowStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Outline counter bubbles", isOn: $document.settings.counterOutline)
                Toggle("Secure pixelate", isOn: $document.settings.securePixelate)
                Toggle("Always snap angles", isOn: $document.settings.alwaysSnap)
            } header: {
                Text("Options")
            } footer: {
                Text("Secure pixelate fills the area from the pixels around it and never uses the hidden content, so it can't be reversed. Turn it off for a classic mosaic, or a blur at thickness 1. With a keyboard, hold Shift to snap angles.")
            }

            Section("Capture") {
                Button("Select Entire Image") { document.selectAll() }
                Button("Clear Annotations", role: .destructive) { document.clearAnnotations() }
                    .disabled(document.annotations.isEmpty)
            }

            Section("Export") {
                Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
                Button(action: onSaveToPhotos) { Label("Save to Photos", systemImage: "photo.badge.plus") }
                Button(action: onSaveToFiles) { Label("Save to Files…", systemImage: "folder") }
            }
            .disabled(document.selection == nil)
        }
        .navigationTitle("Options")
    }
}
