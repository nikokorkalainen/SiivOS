import AppKit
import SwiftUI

/// SiivOS colours. Dark mode is the green look from the design canvas; light mode stays close to
/// standard macOS. Text uses the system's own primary and secondary colours in both modes.
enum SiivOSTheme {
    /// Prominent buttons (Check This Mac, Remove Ticked Items…, Move to Holding Area):
    /// mint (#5EE6A8) in dark mode, moss (#2F7A5F) in light mode.
    static let prominent = adaptive(dark: srgb(0x5EE6A8), light: srgb(0x2F7A5F))

    /// Text on prominent buttons: deep green (#062A20) on mint, white on moss.
    static let onProminent = adaptive(dark: srgb(0x062A20), light: srgb(0xFFFFFF))

    /// Grouped panels: white at 6 % on the green in dark mode, the standard panel colour in light mode.
    static let panel = adaptive(dark: srgb(0xFFFFFF, alpha: 0.06), light: .controlBackgroundColor)

    /// Dividers inside panels: white at 9 % in dark mode, the standard separator in light mode.
    static let divider = adaptive(dark: srgb(0xFFFFFF, alpha: 0.09), light: .separatorColor)
}

/// The window background: a soft diagonal green gradient in dark mode, the normal window colour
/// in light mode. Put it behind the detail column, and use `.scrollContentBackground(.hidden)` on
/// lists and forms so it shows through.
struct SiivOSWindowBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            LinearGradient(
                colors: [
                    Color(nsColor: srgb(0x13563F)),
                    Color(nsColor: srgb(0x0B3A2E)),
                    Color(nsColor: srgb(0x072519)),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
    }
}

/// The sidebar background: deep green in dark mode, with a hint of the window gradient showing
/// through. In light mode it draws nothing, so the standard translucent sidebar stays.
struct SiivOSSidebarBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if colorScheme == .dark {
            ZStack {
                SiivOSWindowBackground()
                Color(nsColor: srgb(0x021A13, alpha: 0.62))
            }
            .ignoresSafeArea()
        } else {
            Color.clear
        }
    }
}

private func srgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func adaptive(dark: NSColor, light: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
    })
}
