import AppKit
import SwiftUI

// Building blocks shared by every screen. The colours themselves are in SiivOSTheme.swift
// and SiivOSIcons.swift; see docs/design.md.

extension Color {
    /// The tint for charts, bars and small marks: mint in dark mode, moss in light mode.
    /// The same colour as the section icons.
    static let siivosTint = SiivOSIconColors.tint
}

extension View {
    /// Left aligned content with a readable maximum width, as the design notes ask.
    func readableWidth() -> some View {
        frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The rounded background used for panels and grouped lists.
    func cardBackground() -> some View {
        background(SiivOSTheme.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(SiivOSTheme.divider)
            )
    }
}

/// The background of a bar pinned to the bottom of a screen. It has to be solid, so that
/// what scrolls underneath does not show through, and it should look like the window
/// continuing. In dark mode it is the bottom edge of the window's green gradient, which
/// runs from #0B3A2E on the left to #072519 on the right; in light mode it is the normal
/// window colour.
struct BottomBarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(red: 11.0 / 255.0, green: 58.0 / 255.0, blue: 46.0 / 255.0),
                    Color(red: 7.0 / 255.0, green: 37.0 / 255.0, blue: 25.0 / 255.0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}

/// A thin line between rows inside a panel, in the theme's divider colour.
struct ThemedDivider: View {
    var body: some View {
        Rectangle()
            .fill(SiivOSTheme.divider)
            .frame(height: 1)
    }
}

/// The arrow that opens and closes a group. 15 pt, as the design notes ask.
struct DisclosureArrow: View {
    let isOpen: Bool

    var body: some View {
        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 20)
            .contentShape(Rectangle())
    }
}

/// The inside of a button: an optional 20 pt symbol, then the title, 8 pt apart.
struct ButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
            }
            Text(title)
        }
    }
}

/// A screen's main button: mint with dark text in dark mode, moss with white text in light
/// mode. 36 pt tall with 8 pt corners, as the design notes ask. Every other button uses
/// `SiivOSButtonStyle`.
struct ProminentButton: View {
    private let title: String
    private let systemImage: String?
    private let isDestructive: Bool
    private let action: () -> Void

    /// - Parameter isDestructive: Fills the button red, for confirming something that
    ///   cannot be undone.
    init(_ title: String, systemImage: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isDestructive = isDestructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(ProminentButtonStyle(isDestructive: isDestructive))
    }
}

/// Draws the main button itself. The Mac's own prominent style picks the text colour for
/// us and keeps it light, which is hard to read on mint, so the theme's colours are
/// applied directly here.
private struct ProminentButtonStyle: ButtonStyle {
    let isDestructive: Bool

    func makeBody(configuration: Configuration) -> some View {
        ProminentButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isDestructive: isDestructive
        )
    }
}

private struct ProminentButtonBody<Content: View>: View {
    let label: Content
    let isPressed: Bool
    let isDestructive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 18)
            .frame(minHeight: 36)
            .background(fillColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.45)
            .contentShape(Rectangle())
    }

    /// Red for a destructive confirmation: #FF8A80 in dark mode, #C9372C in light mode,
    /// the same reds as the red text of `SiivOSButtonStyle`.
    private var fillColor: Color {
        guard isDestructive else {
            return SiivOSTheme.prominent
        }
        return colorScheme == .dark
            ? Color(red: 1.0, green: 0.541, blue: 0.502)
            : Color(red: 0.788, green: 0.216, blue: 0.173)
    }

    private var textColor: Color {
        guard isDestructive else {
            return SiivOSTheme.onProminent
        }
        return colorScheme == .dark ? Color(red: 0.23, green: 0.04, blue: 0.03) : Color.white
    }
}

/// A fact with its value at the far end of the row.
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// A plain bar that fills from the left, for disk space and battery charge.
struct MeterBar: View {
    /// How full the bar is, from 0 to 1.
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(SiivOSTheme.divider)
                Capsule()
                    .fill(Color.siivosTint)
                    .frame(width: proxy.size.width * CGFloat(min(1, max(0, fraction))))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

/// The title of a screen, with one line under it and the screen's main button on the right.
struct PageHeader<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        // Lined up on the title's baseline, so the button's text sits on the same line
        // as the title instead of a little above it.
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle)
                    .bold()
                if let subtitle {
                    Text(subtitle)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            trailing
        }
    }
}

/// The SiivOS loading indicator with the progress text under it, as the design notes ask:
/// the glints, then the text in secondary colour, 18 pt apart.
struct LoadingView: View {
    let text: String

    var body: some View {
        VStack(spacing: 18) {
            GlintLoader()
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

/// The two glints from the logo without the name, for places too narrow for the full logo,
/// such as the collapsed sidebar. The big glint takes the colour of "Siiv" and the small one
/// the colour of "OS", as in the logo.
struct SiivOSGlintMark: View {
    var body: some View {
        Canvas { graphics, canvasSize in
            // The glints as they sit in the logo and the loading animation, on a
            // 120 x 120 grid. Together they cover x 18 to 102 and y 21 to 99.
            let box = CGRect(x: 18, y: 21, width: 84, height: 78)
            let scale = min(canvasSize.width / box.width, canvasSize.height / box.height)
            graphics.translateBy(
                x: (canvasSize.width - box.width * scale) / 2,
                y: (canvasSize.height - box.height * scale) / 2
            )
            graphics.scaleBy(x: scale, y: scale)
            graphics.translateBy(x: -box.minX, y: -box.minY)
            graphics.fill(
                SiivOSGlintShape.path(center: CGPoint(x: 68, y: 55), arm: 34),
                with: .color(SiivOSLogoPaths.siivColor)
            )
            graphics.fill(
                SiivOSGlintShape.path(center: CGPoint(x: 34, y: 83), arm: 16),
                with: .color(SiivOSLogoPaths.osColor)
            )
        }
        .aspectRatio(84.0 / 78.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("SiivOS")
    }
}

/// The outline of one glint, shared by the sidebar mark and the menu bar icon.
enum SiivOSGlintShape {
    /// The SiivOS glint: four points joined by soft curves, with control points at 12 %
    /// and 45.4 % of the arm, as the design notes define it.
    static func path(center c: CGPoint, arm: CGFloat) -> Path {
        let k1 = arm * 0.12
        let k2 = arm * 0.454
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - arm))
        path.addCurve(to: CGPoint(x: c.x + arm, y: c.y), control1: CGPoint(x: c.x + k1, y: c.y - k2), control2: CGPoint(x: c.x + k2, y: c.y - k1))
        path.addCurve(to: CGPoint(x: c.x, y: c.y + arm), control1: CGPoint(x: c.x + k2, y: c.y + k1), control2: CGPoint(x: c.x + k1, y: c.y + k2))
        path.addCurve(to: CGPoint(x: c.x - arm, y: c.y), control1: CGPoint(x: c.x - k1, y: c.y + k2), control2: CGPoint(x: c.x - k2, y: c.y + k1))
        path.addCurve(to: CGPoint(x: c.x, y: c.y - arm), control1: CGPoint(x: c.x - k2, y: c.y - k1), control2: CGPoint(x: c.x - k1, y: c.y - k2))
        path.closeSubpath()
        return path
    }
}

/// Lays a start screen out in the open: its content centred in the content column, with
/// nothing behind it. If the window is too small, the content scrolls.
struct CenteredScreen<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(32)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
        }
    }
}

/// A rounded box that holds one topic.
struct Card<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardBackground()
    }
}

/// Finds a name people recognise for folders that are named after an app's identifier.
@MainActor
enum ReadableNames {
    private static var known: [String: String] = [:]

    /// The app's name for items named like "com.example.Notes" when that app can be
    /// found, otherwise the item's own name.
    static func name(for url: URL) -> String {
        let fileName = url.lastPathComponent
        if let name = known[fileName] {
            return name
        }
        let name = appName(forItemNamed: fileName) ?? fileName
        known[fileName] = name
        return name
    }

    private static func appName(forItemNamed fileName: String) -> String? {
        var identifier = fileName
        for ending in [".savedState", ".plist", ".binarycookies"] where identifier.hasSuffix(ending) {
            identifier.removeLast(ending.count)
        }
        guard identifier.split(separator: ".").count >= 3,
              !identifier.contains(" "),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else {
            return nil
        }
        let shown = FileManager.default.displayName(atPath: appURL.path)
        return shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
    }
}
