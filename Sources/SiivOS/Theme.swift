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

/// The inside of a button: an optional 20 pt symbol, then the title.
struct ButtonLabel: View {
    let title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 20))
            }
            Text(title)
        }
    }
}

/// A screen's main button: mint with dark text in dark mode, moss with white text in light mode.
struct ProminentButton: View {
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(ProminentButtonStyle())
    }
}

/// Draws the main button itself. The Mac's own prominent style picks the text colour for
/// us and keeps it light, which is hard to read on mint, so the theme's colours are
/// applied directly here.
private struct ProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ProminentButtonBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct ProminentButtonBody<Content: View>: View {
    let label: Content
    let isPressed: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize

    var body: some View {
        label
            .font(.body.weight(.medium))
            .foregroundStyle(SiivOSTheme.onProminent)
            .padding(.horizontal, controlSize == .large ? 14 : 10)
            .padding(.vertical, controlSize == .large ? 6 : 3)
            .background(SiivOSTheme.prominent, in: RoundedRectangle(cornerRadius: 7))
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.45)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

/// In dark mode, gives the window's title bar the same green as the top of the content,
/// so there is no grey strip above the green look. Light mode keeps the standard bar.
struct ThemedToolbar: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
                .toolbarBackground(
                    LinearGradient(
                        colors: [
                            Color(red: 19.0 / 255.0, green: 86.0 / 255.0, blue: 63.0 / 255.0),
                            Color(red: 11.0 / 255.0, green: 58.0 / 255.0, blue: 46.0 / 255.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    for: .windowToolbar
                )
                .toolbarBackground(.visible, for: .windowToolbar)
        } else {
            content
        }
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
        HStack(alignment: .top) {
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
