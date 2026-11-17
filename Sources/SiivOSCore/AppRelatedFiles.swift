import Foundation

/// A file or folder in the user's Library that an app created for itself.
public struct RelatedItem: Equatable, Identifiable, Sendable {
    public let url: URL
    /// Space the item takes on disk, in bytes.
    public let sizeBytes: Int64
    /// What the item is, in plain words, for example "Settings".
    public let kind: String

    public var id: URL { url }
}

/// Finds what an app has stored outside its own bundle, so that uninstalling can take
/// it along. Read-only.
///
/// Items are matched by the app's identifier ("com.example.Notes") or, in the folders
/// where apps commonly use it, by the app's exact name. Folders that several apps of one
/// developer share under a different name are not found.
public enum AppRelatedFiles {
    private enum Match {
        /// The item is named exactly after the identifier, or after the app's name if allowed.
        case exact(allowsAppName: Bool)
        /// The item is the identifier followed by this ending.
        case identifierWithSuffix(String)
        /// The item starts with the identifier and a dot, and ends in ".plist".
        case identifierPrefixedPlist
    }

    private static let locations: [(folder: String, kind: String, match: Match)] = [
        ("Application Support", "Stored data", .exact(allowsAppName: true)),
        ("Caches", "Cache", .exact(allowsAppName: true)),
        ("Logs", "Logs", .exact(allowsAppName: true)),
        ("Containers", "Stored data", .exact(allowsAppName: false)),
        ("HTTPStorages", "Web data", .exact(allowsAppName: false)),
        ("WebKit", "Web data", .exact(allowsAppName: false)),
        ("Application Scripts", "Scripts", .exact(allowsAppName: false)),
        ("Preferences", "Settings", .identifierWithSuffix(".plist")),
        ("Preferences/ByHost", "Settings", .identifierPrefixedPlist),
        ("Saved Application State", "Saved window state", .identifierWithSuffix(".savedState")),
        ("Cookies", "Cookies", .identifierWithSuffix(".binarycookies")),
        ("LaunchAgents", "Background item", .identifierPrefixedPlist)
    ]

    public static func find(
        for app: InstalledApp,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) -> [RelatedItem] {
        let library = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        let identifier = app.bundleIdentifier?.lowercased()
        // Very short names are too likely to match something unrelated.
        let appName = app.name.count >= 3 ? app.name.lowercased() : nil

        var found: [RelatedItem] = []
        var seenPaths = Set<String>()
        func add(_ url: URL, kind: String) {
            guard seenPaths.insert(url.standardizedFileURL.path).inserted else {
                return
            }
            found.append(
                RelatedItem(url: url, sizeBytes: FileSize.onDisk(of: url, fileManager: fileManager), kind: kind)
            )
        }

        for location in locations {
            let directory = library.appendingPathComponent(location.folder, isDirectory: true)
            let children = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for child in children {
                let name = child.lastPathComponent.lowercased()
                if matches(name, location.match, identifier: identifier, appName: appName) {
                    add(child, kind: location.kind)
                }
            }
        }

        // Background items that start a program inside the app, whatever they are called.
        let agents = BackgroundItems.find(
            in: [(library.appendingPathComponent("LaunchAgents", isDirectory: true), .user)],
            fileManager: fileManager
        )
        let insideApp = app.url.standardizedFileURL.path + "/"
        for agent in agents {
            if let program = agent.program, program.hasPrefix(insideApp) {
                add(agent.url, kind: "Background item")
            }
        }

        return found
    }

    private static func matches(_ name: String, _ match: Match, identifier: String?, appName: String?) -> Bool {
        switch match {
        case .exact(let allowsAppName):
            if let identifier, name == identifier {
                return true
            }
            if allowsAppName, let appName, name == appName {
                return true
            }
            return false
        case .identifierWithSuffix(let suffix):
            guard let identifier else { return false }
            return name == identifier + suffix.lowercased()
        case .identifierPrefixedPlist:
            guard let identifier else { return false }
            return name.hasPrefix(identifier + ".") && name.hasSuffix(".plist")
        }
    }
}
