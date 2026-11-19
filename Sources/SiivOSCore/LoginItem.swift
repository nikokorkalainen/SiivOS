import Foundation
#if os(macOS)
import ServiceManagement
#endif

/// Whether SiivOS opens by itself when the user logs in to the Mac.
///
/// This is the user's own choice, made in Settings, and it is off until they turn it
/// on. macOS keeps the list of such apps itself, shows SiivOS in System Settings under
/// Login Items, and lets the user switch it off there too.
public enum LoginItem {
    public enum Status: Equatable, Sendable {
        /// SiivOS opens at login.
        case on
        /// SiivOS does not open at login.
        case off
        /// The user asked for it, but macOS wants them to allow it in System Settings first.
        case needsApproval
        /// This copy of SiivOS cannot be opened at login, because it is not an app that
        /// macOS can find again: it was started from Xcode or from Terminal.
        case unavailable
    }

    public enum Failure: LocalizedError {
        case notAnApp

        public var errorDescription: String? {
            switch self {
            case .notAnApp:
                return tr("This copy of SiivOS was not started as an app, so macOS cannot open it at login. Use the app built with Scripts/make-app.sh.")
            }
        }
    }

    /// True when SiivOS is running as an app that macOS can open again by itself.
    public static var isRunningAsApp: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    /// What macOS says right now. Only reads.
    public static var status: Status {
        guard isRunningAsApp else {
            return .unavailable
        }
        #if os(macOS)
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .needsApproval
        default:
            return .off
        }
        #else
        return .unavailable
        #endif
    }

    /// Turns opening at login on or off. Nothing is changed when this copy of SiivOS is
    /// not an app, which also keeps the tests from ever adding anything to the Mac.
    public static func set(_ isOn: Bool) throws {
        guard isRunningAsApp else {
            throw Failure.notAnApp
        }
        #if os(macOS)
        if isOn {
            try SMAppService.mainApp.register()
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }
        #else
        throw Failure.notAnApp
        #endif
    }
}
