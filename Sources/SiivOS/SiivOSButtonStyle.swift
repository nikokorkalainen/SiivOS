import SwiftUI

/// Button styles for everything that is not the screen's main action, so every button in SiivOS
/// shares one look. The main action keeps using `ProminentButton`.
///
/// | Style        | Height | Corners | Text            | Look                               |
/// |--------------|--------|---------|-----------------|------------------------------------|
/// | `.prominent` | 36 pt  | 8 pt    | 14 pt semibold  | `ProminentButton` (mint or moss)   |
/// | `.standard`  | 36 pt  | 8 pt    | 14 pt medium    | soft panel with a thin outline     |
/// | `.small`     | 30 pt  | 7 pt    | 13 pt medium    | same as standard, for rows         |
/// | destructive  | either | either  | red text        | same panel, red text               |
///
///     Button(tr("Open Activity Monitor")) { … }
///         .buttonStyle(SiivOSButtonStyle(.standard))
///     Button(tr("Delete Permanently…")) { … }
///         .buttonStyle(SiivOSButtonStyle(.small, destructive: true))
struct SiivOSButtonStyle: ButtonStyle {
    enum Size {
        /// Header buttons and dialog buttons: Scan Again, Open Activity Monitor, Cancel.
        case standard
        /// Buttons inside rows and cards: Review, Tick All, Put Back, Open Cleanup.
        case small
    }

    var size: Size
    var destructive: Bool

    init(_ size: Size = .standard, destructive: Bool = false) {
        self.size = size
        self.destructive = destructive
    }

    func makeBody(configuration: Configuration) -> some View {
        SiivOSButtonBody(configuration: configuration, size: size, destructive: destructive)
    }
}

private struct SiivOSButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let size: SiivOSButtonStyle.Size
    let destructive: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let height: CGFloat = size == .standard ? 36 : 30
        let corner: CGFloat = size == .standard ? 8 : 7
        configuration.label
            .font(.system(size: size == .standard ? 14 : 13, weight: .medium))
            .foregroundStyle(destructive ? redText : Color.primary)
            .padding(.horizontal, size == .standard ? 16 : 12)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(configuration.isPressed ? pressedPanel : panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(outline, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1 : 0.45)
    }

    /// White at 9 % on the green; a light grey in light mode.
    private var panel: Color {
        colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.05)
    }

    private var pressedPanel: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.10)
    }

    private var outline: Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.12)
    }

    /// #FF8A80 in dark mode, #C9372C in light mode.
    private var redText: Color {
        colorScheme == .dark
            ? Color(red: 1.0, green: 0.541, blue: 0.502)
            : Color(red: 0.788, green: 0.216, blue: 0.173)
    }
}
