import SwiftUI

/// The logo at the top of the sidebar: the name with the two glints, no app icon.
///
/// Add it above the sections, for example on the sidebar `List`:
///
///     .safeAreaInset(edge: .top) { SiivOSSidebarHeader() }
struct SiivOSSidebarHeader: View {
    var body: some View {
        SiivOSLogo()
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 14)
    }
}
