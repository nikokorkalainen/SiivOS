import AppKit
import SwiftUI

/// The logo at the top of the sidebar: the app icon next to the name.
///
/// Add it above the sections, for example on the sidebar `List`:
///
///     .safeAreaInset(edge: .top) { SiivOSSidebarHeader() }
struct SiivOSSidebarHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            // The icon from the app bundle (Resources/AppIcon.icns, added by make-app.sh).
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)
            SiivOSWordmark()
                .frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("SiivOS")
    }
}
