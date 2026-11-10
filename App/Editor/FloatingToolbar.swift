import EmberKit
import SwiftUI

/// One round button around the selection.
struct ToolbarButtonModel: Identifiable {
    enum Kind {
        case action(() -> Void)
        case share(RenderedCapture)
    }

    let id: String
    let title: String
    let systemImage: String
    var isActive = false
    var isEnabled = true
    /// Shown instead of the icon (the colour button).
    var swatch: RGBAColor?
    var shortcut: KeyboardShortcut?
    let kind: Kind
}

/// Flameshot's signature toolbar: round buttons that wrap around the
/// selection (placement from `ToolbarLayout`).
struct FloatingToolbar: View {
    let items: [ToolbarButtonModel]
    let selection: CGRect
    let bounds: CGRect

    static let buttonSize: CGFloat = 44 // Apple's minimum touch target
    static let spacing: CGFloat = 6

    var body: some View {
        let centers = ToolbarLayout.centers(
            count: items.count, selection: selection, bounds: bounds,
            buttonSize: Self.buttonSize, spacing: Self.spacing
        )
        ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index < centers.count {
                    ToolbarButton(item: item).position(centers[index])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct ToolbarButton: View {
    let item: ToolbarButtonModel

    var body: some View {
        Group {
            switch item.kind {
            case .action(let action):
                Button(action: action) { label }
                    .keyboardShortcut(item.shortcut)
                    .disabled(!item.isEnabled)
            case .share(let capture):
                ShareLink(item: capture, preview: SharePreview("Ember capture", image: Image(systemName: "photo"))) {
                    label
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.lift)
        .help(item.title)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(item.isActive ? .isSelected : [])
    }

    private var label: some View {
        ZStack {
            Circle().fill(item.isActive ? Color.white : Color.emberPurple)
            if let swatch = item.swatch {
                Circle()
                    .fill(Color(swatch))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .padding(9)
            } else {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.isActive ? Color.emberPurple : .white)
            }
        }
        .frame(width: FloatingToolbar.buttonSize, height: FloatingToolbar.buttonSize)
        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
        .opacity(item.isEnabled ? 1 : 0.45)
        .contentShape(Circle())
    }
}

// MARK: - Radial colour picker

struct PickerSession: Equatable {
    /// View coordinates.
    var center: CGPoint
    var highlighted: Int?
    /// Opened by a button / squeeze: choose with a tap. Otherwise the press
    /// that opened it is still down and lifting commits (Flameshot style).
    var tapMode: Bool
}

/// Flameshot's colour wheel: swatches on a ring, starting at 12 o'clock. The
/// last slot opens the full colour picker in the side panel.
struct RadialColorPicker: View {
    let session: PickerSession
    let current: RGBAColor
    var onSelect: (Int) -> Void
    var onDismiss: () -> Void

    static let palette = RGBAColor.defaultPalette
    static var slotCount: Int { palette.count + 1 }
    static let radius = RadialLayout.radius(count: slotCount, buttonSize: 60)
    static let swatchSize: CGFloat = 44

    var body: some View {
        let centers = RadialLayout.centers(count: Self.slotCount, around: session.center, radius: Self.radius)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001) // catches taps outside the wheel
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: (Self.radius + Self.swatchSize) * 2, height: (Self.radius + Self.swatchSize) * 2)
                .position(session.center)

            ForEach(0..<Self.slotCount, id: \.self) { i in
                swatch(i)
                    .scaleEffect(session.highlighted == i ? 1.25 : 1)
                    .position(centers[i])
                    .onTapGesture { onSelect(i) }
            }

            Circle()
                .fill(Color(current))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .frame(width: 28, height: 28)
                .position(session.center)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(session.tapMode)
        .animation(.spring(duration: 0.15), value: session.highlighted)
    }

    @ViewBuilder
    private func swatch(_ i: Int) -> some View {
        let isSelected = i < Self.palette.count && Self.palette[i] == current
        Group {
            if i < Self.palette.count {
                Circle().fill(Color(Self.palette[i]))
            } else {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .overlay(Image(systemName: "plus").font(.headline).foregroundStyle(.white))
            }
        }
        .overlay(Circle().strokeBorder(.white, lineWidth: isSelected ? 4 : 2))
        .frame(width: Self.swatchSize, height: Self.swatchSize)
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .accessibilityLabel(i < Self.palette.count ? "Colour \(i + 1)" : "Custom colour")
    }
}
