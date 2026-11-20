import AppKit
import SiivOSCore
import SwiftUI

@main
struct SiivOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Whether SiivOS shows itself in the menu bar. Changed in Settings.
    @AppStorage(AppSettings.showsMenuBarKey) private var showsMenuBar = true
    /// The size the window's content was last left in, which is the size a new window
    /// opens in. Kept up to date by `MainWindow`.
    @AppStorage(MainWindow.contentWidthKey) private var windowWidth = Double(MainWindow.defaultSize.width)
    @AppStorage(MainWindow.contentHeightKey) private var windowHeight = Double(MainWindow.defaultSize.height)

    var body: some Scene {
        WindowGroup("SiivOS", id: MainWindow.sceneID) {
            ContentView()
                .frame(minWidth: 820, minHeight: 520)
        }
        // No title bar strip: the sidebar and the content run to the top of the window,
        // with the window buttons over the sidebar. Each screen shows its own title.
        .windowStyle(.hiddenTitleBar)
        // A new window opens in the size the last one was left in.
        .defaultSize(width: windowWidth, height: windowHeight)
        .commands {
            SettingsCommands()
        }

        // The glints in the menu bar, with a small panel under them.
        MenuBarExtra(isInserted: $showsMenuBar) {
            MenuBarPanel()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

/// "Settings…" in the SiivOS menu, with Command-comma. Settings is a screen in the main
/// window, so this brings the window forward on that screen.
struct SettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(tr("Settings…")) {
                MainWindow.show(.settings, openWindow: openWindow)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var readingTimer: Timer?
    private var quietStartTimer: Timer?
    private var quietStartTriesLeft = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything else, so that a click on a notification that started SiivOS
        // reaches it.
        ChangeNotifications.start()

        if Self.wasOpenedAtLogin && AppSettings.showsMenuBar {
            // Opened by macOS at login, not by the user: stay in the menu bar, out of
            // the Dock, and do not put a window in front of whatever they are doing.
            QuietStart.isUnderWay = true
            NSApp.setActivationPolicy(.accessory)
            startQuietly()
        } else {
            // When run straight from Xcode or `swift run` there is no app bundle,
            // so ask macOS to treat this as a normal windowed app with a Dock icon.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }

        // Take a health reading now unless there is a recent one, and look again every
        // half hour for as long as SiivOS runs, which with the menu bar icon can be all
        // day. A reading is only taken when the last one is six hours old. Only reads.
        // The same moments are used to empty the holding area of what has waited longer
        // than the user chose in Settings. That does nothing unless a time is chosen.
        Task { @MainActor in
            TimelineModel.shared.updateIfDue()
            HoldingStatus.shared.emptyIfDue()
        }
        readingTimer = Timer.scheduledTimer(withTimeInterval: 1_800, repeats: true) { _ in
            Task { @MainActor in
                TimelineModel.shared.updateIfDue()
                HoldingStatus.shared.emptyIfDue()
            }
        }
    }

    /// True when macOS opened SiivOS because the user logged in, and not because they
    /// opened it themselves. macOS says so in the message it starts the app with.
    private static var wasOpenedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        // The four-letter codes macOS uses: "oapp" (open application), "prdt" (the
        // reason) and "lgit" (launched as a login item).
        let openApplication: UInt32 = 0x6F61_7070
        let reason: UInt32 = 0x7072_6474
        let loginItem: UInt32 = 0x6C67_6974
        return event.eventID == openApplication
            && event.paramDescriptor(forKeyword: reason)?.enumCodeValue == loginItem
    }

    /// Closes the window SiivOS opens when it starts, leaving it in the menu bar. The
    /// window appears a moment after launch, so this looks for it a few times and stops
    /// as soon as it has closed it, or after two seconds.
    private func startQuietly() {
        quietStartTriesLeft = 40
        quietStartTimer = Timer.scheduledTimer(
            timeInterval: 0.05,
            target: self,
            selector: #selector(closeWindowOpenedAtStart),
            userInfo: nil,
            repeats: true
        )
    }

    @MainActor
    @objc private func closeWindowOpenedAtStart() {
        quietStartTriesLeft -= 1
        let windows = NSApp.windows.filter { $0.canBecomeMain && $0.isVisible }
        for window in windows {
            window.close()
        }
        if !windows.isEmpty || quietStartTriesLeft <= 0 {
            quietStartTimer?.invalidate()
            quietStartTimer = nil
            // From here on a window that opens brings the Dock icon with it.
            QuietStart.isUnderWay = false
        }
    }

    /// With the menu bar icon on, closing the window leaves SiivOS running in the menu
    /// bar, and `DockIcon` takes it out of the Dock. Without it, closing the window
    /// quits the app as before.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !AppSettings.showsMenuBar
    }
}
