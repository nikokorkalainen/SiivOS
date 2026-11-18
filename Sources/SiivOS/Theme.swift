import AppKit
import SwiftUI

// The look shared by every screen. See docs/design.md.

extension Color {
    /// Moss green (#2F7A5F): filled buttons and other accents, in light and dark mode.
    static let siivosMoss = Color(red: 47.0 / 255.0, green: 122.0 / 255.0, blue: 95.0 / 255.0)

    /// Lichen (#9CCBB0): the lighter green used where moss would be too dark.
    static let siivosLichen = Color(red: 156.0 / 255.0, green: 203.0 / 255.0, blue: 176.0 / 255.0)

    /// For tinted icons and links: moss in light mode, lichen in dark mode.
    static let siivosTint = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 156.0 / 255.0, green: 203.0 / 255.0, blue: 176.0 / 255.0, alpha: 1)
        }
        return NSColor(srgbRed: 47.0 / 255.0, green: 122.0 / 255.0, blue: 95.0 / 255.0, alpha: 1)
    })

    /// The background of cards and grouped lists.
    static let siivosCard = Color(nsColor: .controlBackgroundColor)
}

extension View {
    /// Left aligned content with a readable maximum width, as the design notes ask.
    func readableWidth() -> some View {
        frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The rounded background used for cards and grouped lists.
    func cardBackground() -> some View {
        background(Color.siivosCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
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
