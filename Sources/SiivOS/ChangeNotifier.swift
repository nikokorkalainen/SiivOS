import AppKit
import SiivOSCore
import SwiftUI
import UserNotifications

/// Receives what macOS reports about SiivOS's notifications: that one is about to be
/// shown, or that the user clicked one.
private final class NotificationEvents: NSObject, UNUserNotificationCenterDelegate {
    /// Shows the notification even when SiivOS is the app in front: the user may be on
    /// another screen of it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }

    /// A click on the notification opens the Health Timeline, where the change is listed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            ChangeNotifier.shared.showTimeline()
        }
        completionHandler()
    }
}

/// The parts of the notifications that have to be in place the moment SiivOS starts.
enum ChangeNotifications {
    private static let events = NotificationEvents()
    /// When this copy of SiivOS started.
    private(set) static var launchedAt = Date()

    /// True when SiivOS runs as an app. Only an app can show notifications; a copy
    /// started from Xcode or Terminal has no place in the Mac's notification settings.
    static var isAvailable: Bool {
        LoginItem.isRunningAsApp
    }

    /// Called once when SiivOS starts, so that a click on a notification reaches it.
    static func start() {
        launchedAt = Date()
        guard isAvailable else {
            return
        }
        UNUserNotificationCenter.current().delegate = events
    }
}

/// Shows a notification when the Health Timeline notices a change worth a second
/// glance: something new that starts by itself, a new configuration profile, or one of
/// macOS's protections turned off. Off unless turned on in Settings. A notification is
/// made on this Mac and sent nowhere.
@MainActor
final class ChangeNotifier: ObservableObject {
    static let shared = ChangeNotifier()

    /// What macOS says about SiivOS showing notifications.
    enum Permission {
        /// Not asked yet, or not looked up yet.
        case unknown
        case allowed
        /// The user, or the Mac's settings, said no.
        case denied
        /// This copy of SiivOS is not an app, so it cannot show notifications at all.
        case unavailable
    }

    /// Whether the user has asked for notifications.
    @Published private(set) var isOn: Bool
    @Published private(set) var permission: Permission

    private static let isOnKey = "notifiesAboutChanges"
    private static let toldUpToKey = "changesToldUpTo"

    private init() {
        isOn = UserDefaults.standard.bool(forKey: Self.isOnKey)
        permission = ChangeNotifications.isAvailable ? .unknown : .unavailable
    }

    /// The moment up to which changes have been told about. Changes noticed before
    /// notifications were turned on are never told about.
    private var toldUpTo: Date? {
        get {
            let seconds = UserDefaults.standard.double(forKey: Self.toldUpToKey)
            return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: Self.toldUpToKey)
        }
    }

    /// Turns notifications on or off. Turning them on makes macOS ask the user, the
    /// first time, whether SiivOS may show notifications.
    func setOn(_ on: Bool) {
        guard ChangeNotifications.isAvailable else {
            return
        }
        isOn = on
        UserDefaults.standard.set(on, forKey: Self.isOnKey)
        guard on else {
            return
        }
        // Start from now: what was noticed earlier is already in the Health Timeline.
        toldUpTo = Date()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
            Task { @MainActor in
                ChangeNotifier.shared.permission = granted ? .allowed : .denied
            }
        }
    }

    /// Looks up what macOS says right now. It can change in System Settings at any time.
    func refreshPermission() {
        guard ChangeNotifications.isAvailable else {
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .denied:
                    ChangeNotifier.shared.permission = .denied
                case .notDetermined:
                    ChangeNotifier.shared.permission = .unknown
                default:
                    ChangeNotifier.shared.permission = .allowed
                }
            }
        }
    }

    /// Called after every reading: shows a notification if the reading noticed
    /// something worth a second glance that has not been told about yet.
    func tellAboutChanges(in history: HealthHistory) {
        guard isOn, ChangeNotifications.isAvailable else {
            return
        }
        guard let after = toldUpTo else {
            toldUpTo = Date()
            return
        }
        guard let notice = ChangeNotices.notice(for: history, after: after) else {
            return
        }
        toldUpTo = notice.coversUpTo

        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Opens the Health Timeline, where the change the notification was about is listed.
    func showTimeline() {
        AppNavigation.shared.selection = .timeline
        // Started by the click itself, SiivOS is about to open its window anyway, and
        // asking for one here would open a second.
        let hasJustStarted = Date().timeIntervalSince(ChangeNotifications.launchedAt) < 3
        if let openWindow = MainWindow.opener, !hasJustStarted {
            MainWindow.show(.timeline, openWindow: openWindow)
        } else {
            NSApp.activate()
        }
    }
}
