import Foundation

/// The kinds of data SiivOS never offers for cleanup, however much space they take.
///
/// This list decides what the scanners may suggest. It errs on the side of leaving
/// things out: an item wrongly held back costs a little disk space, an item wrongly
/// offered could sign the user out of everything or look like tampering to an employer.
///
/// It does not stop the user from removing something deliberately, for example by
/// uninstalling a password manager. Those choices are explained and confirmed one by one.
public enum NeverOffer {
    public enum Category: String, CaseIterable, Sendable {
        case macOS
        case signIn
        case sync
        case security

        public var title: String {
            switch self {
            case .macOS: return tr("macOS itself")
            case .signIn: return tr("Sign-in, passwords and payment")
            case .sync: return tr("iCloud and other syncing")
            case .security: return tr("Security and device management")
            }
        }

        /// Why this kind of data is left alone, in plain words.
        public var explanation: String {
            switch self {
            case .macOS:
                return tr("Data that belongs to macOS and Apple's own apps. macOS looks after it, and clearing it while it is in use can leave parts of the system blank until you log out.")
            case .signIn:
                return tr("Data from password managers, authenticators and the parts of macOS that keep you signed in. Clearing it can sign you out everywhere, and it takes almost no space.")
            case .sync:
                return tr("The records that iCloud and other syncing services use to know what is already up to date. Clearing them can make everything sync again from the start.")
            case .security:
                return tr("Data from antivirus, security and device-management software. On a Mac managed by an employer, touching it can look like someone tampering with the machine.")
            }
        }
    }

    /// Names that mark data as belonging to sign-in, passwords or payment.
    private static let signInWords = [
        "account", "appleid", "authkit", "authentication", "authorization", "identityservice",
        "keychain", "passkit", "wallet", "1password", "agilebits", "bitwarden", "lastpass",
        "dashlane", "keepass", "nordpass", "enpass", "proton.pass", "authy", "yubico", "duosecurity"
    ]

    /// Names that mark data as belonging to a syncing service.
    private static let syncWords = [
        "icloud", "cloudkit", "clouddocs", "familycircle", "screentime", "homekit", "itunescloud",
        "dropbox", "onedrive", "googledrive", "drivefs", "syncthing", "nextcloud"
    ]

    /// Names that mark data as belonging to security or device-management software.
    private static let securityWords = [
        "crowdstrike", "sentinelone", "sentinel-labs", "jamf", "sophos", "malwarebytes", "kandji",
        "carbonblack", "zscaler", "netskope", "intune", "companyportal", "mosyle", "addigy",
        "bitdefender", "kaspersky", "trendmicro", "symantec", "mcafee", "paloaltonetworks",
        "globalprotect", "anyconnect", "secureclient", "fleetdm", "tanium", "wdav", "defender"
    ]

    /// Identifier beginnings for security vendors whose names are too short to search for
    /// safely ("eset" is also part of "preset").
    private static let securityPrefixes = ["com.eset.", "com.okta.", "com.cisco.", "com.elastic."]

    /// The reason an item with this name must not be offered for cleanup, or `nil` when it may be.
    ///
    /// - Parameter name: The file or folder name, for example "com.example.Notes".
    public static func category(forItemNamed name: String) -> Category? {
        let lowered = name.lowercased()

        if lowered == "com.apple" || lowered.hasPrefix("com.apple.") {
            return .macOS
        }
        if signInWords.contains(where: { lowered.contains($0) }) {
            return .signIn
        }
        if syncWords.contains(where: { lowered.contains($0) }) {
            return .sync
        }
        if securityWords.contains(where: { lowered.contains($0) })
            || securityPrefixes.contains(where: { lowered.hasPrefix($0) }) {
            return .security
        }
        return nil
    }
}

/// An app that is open right now. The app's screens gather these and hand them to the
/// scanners, which then hold back that app's data.
public struct RunningApp: Equatable, Sendable {
    public let name: String
    public let bundleIdentifier: String?

    public init(name: String, bundleIdentifier: String?) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    /// The open app that an item with this name belongs to, if any.
    ///
    /// An item belongs to an app when it is named after the app's identifier
    /// ("com.example.Notes"), after something inside or above that identifier
    /// ("com.example.Notes.helper", "com.example"), after the developer part alone
    /// ("example"), or after the app's own name ("Notes").
    static func using(itemNamed name: String, among apps: [RunningApp]) -> RunningApp? {
        let item = name.lowercased()
        return apps.first { app in
            if item.count >= 3, item == app.name.lowercased() {
                return true
            }
            guard let identifier = app.bundleIdentifier?.lowercased(), !identifier.isEmpty else {
                return false
            }
            if item == identifier || item.hasPrefix(identifier + ".") {
                return true
            }
            if item.contains("."), identifier.hasPrefix(item + ".") {
                return true
            }
            let parts = identifier.split(separator: ".")
            return parts.count >= 2 && item.count >= 3 && item == String(parts[1])
        }
    }
}
