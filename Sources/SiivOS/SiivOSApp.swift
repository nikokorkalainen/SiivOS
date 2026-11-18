import AppKit
import SwiftUI

@main
struct SiivOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Whether SiivOS shows itself in the menu bar. Changed in Settings.
    @AppStorage(AppSettings.showsMenuBarKey) private var showsMenuBar = true

    var body: some Scene {
        WindowGroup("SiivOS", id: MainWindow.sceneID) {
            ContentView()
                .frame(minWidth: 820, minHeight: 520)
        }
        // No title bar strip: the sidebar and the content run to the top of the window,
        // with the window buttons over the sidebar. Each screen shows its own title.
        .windowStyle(.hiddenTitleBar)

        // The glints in the menu bar, with a small panel under them.
        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarPanel()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var readingTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // When run straight from Xcode or `swift run` there is no app bundle,
        // so ask macOS to treat this as a normal windowed app with a Dock icon.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // Take a health reading now unless there is a recent one, and look again every
        // half hour for as long as SiivOS runs, which with the menu bar icon can be all
        // day. A reading is only taken when the last one is six hours old. Only reads.
        Task { @MainActor in
            TimelineModel.shared.updateIfDue()
        }
        readingTimer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { _ in
            Task { @MainActor in
                TimelineModel.shared.updateIfDue()
            }
        }
    }

    /// With the menu bar icon on, closing the window leaves SiivOS running in the menu
    /// bar. Without it, closing the window quits the app as before.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.showsMenuBar
    }
}
