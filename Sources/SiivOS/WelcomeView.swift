import AppKit
import SiivOSCore
import SwiftUI

/// Whether the welcome has been shown on this Mac.
enum Welcome {
    static let hasBeenSeenKey = "hasSeenWelcome"

    static var hasBeenSeen: Bool {
        UserDefaults.standard.bool(forKey: hasBeenSeenKey)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: hasBeenSeenKey)
    }
}

/// Shown once, the first time SiivOS opens: what it does, what it never does without
/// asking, and the one permission that makes it more useful. It changes nothing, and
/// can be opened again from Settings.
struct WelcomeView: View {
    let onDone: () -> Void

    /// Whether macOS lets SiivOS see every folder. Looked up again when SiivOS comes
    /// forward, for example after a visit to System Settings.
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 12) {
                SiivOSLogo()
                    .frame(height: 39)
                Text(tr("Welcome to SiivOS"))
                    .font(.title2)
                    .bold()
                Text(tr("SiivOS frees up space, shows what is slowing this Mac down and keeps an eye on what changes on it. Three things to know before you start:"))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                point(
                    .history,
                    tr("You decide, and you can undo"),
                    tr("Nothing is removed without showing you first what will happen. What you remove waits in a holding area, and History puts it back with one click.")
                )
                point(
                    .cleanup,
                    tr("Honest labels"),
                    tr("Everything Cleanup finds is labelled Safe to remove or Check first, with the reason. No scare numbers.")
                )
                point(
                    .protection,
                    tr("It stays on this Mac"),
                    tr("No account, no tracking, no ads. SiivOS sends nothing anywhere, and uses the network only if you ask it to download virus definitions.")
                )
            }

            permission

            HStack {
                Spacer()
                ProminentButton(tr("Get Started"), action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 580)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
    }

    /// One of the three things to know: an icon from the SiivOS set, a heading and a
    /// sentence or two.
    private func point(_ icon: SiivOSIcon, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SiivOSIconView(icon, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .fontWeight(.semibold)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Full Disk Access: what it is for, whether SiivOS has it, and the way to the page
    /// in System Settings where only the user can turn it on.
    private var permission: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Full Disk Access"))
                    .fontWeight(.semibold)
                Spacer()
                SettingStatus(isOn: hasFullDiskAccess)
            }
            if hasFullDiskAccess {
                Text(tr("macOS lets SiivOS see every folder, so it does not ask folder by folder."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("This one permission is optional, and it makes SiivOS more useful: macOS stops asking about one folder at a time, and SiivOS can show which apps hold which permissions. Only you can turn it on. Open the page below and switch SiivOS on in the list, now or later from Settings."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Open Full Disk Access Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SiivOSButtonStyle(.standard))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}
