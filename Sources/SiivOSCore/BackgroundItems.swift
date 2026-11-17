import Foundation

/// A program that macOS starts by itself, described by a settings file in one of the
/// "LaunchAgents" or "LaunchDaemons" folders.
public struct BackgroundItem: Equatable, Identifiable, Sendable {
    public enum Scope: String, Sendable {
        /// Starts for this user only. Lives in the user's own Library.
        case user
        /// Starts for every user of this Mac when they log in.
        case allUsers
        /// Starts with the Mac itself, before anyone logs in.
        case system
    }

    /// The settings file that makes macOS start the program.
    public let url: URL
    /// The item's own name for itself, for example "com.example.updater".
    public let label: String
    /// Path of the program that gets started, if the file names one.
    public let program: String?
    public let scope: Scope
    /// True when the program starts at login or startup, not only when something asks for it.
    public let startsAutomatically: Bool
    /// True when the file itself says the item is turned off.
    public let isDisabled: Bool
    /// False when the program the file points to is gone, which usually means the app
    /// it belonged to was removed.
    public let programExists: Bool

    public var id: URL { url }
}

/// Finds background items. Read-only.
public enum BackgroundItems {
    /// The folders where background items are registered, with who each one applies to.
    public static func standardDirectories(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> [(directory: URL, scope: BackgroundItem.Scope)] {
        [
            (homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true), .user),
            (URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true), .allUsers),
            (URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true), .system)
        ]
    }

    /// Every background item registered in the given folders, sorted by name.
    public static func find(
        in directories: [(directory: URL, scope: BackgroundItem.Scope)],
        fileManager: FileManager = .default
    ) -> [BackgroundItem] {
        var items: [BackgroundItem] = []
        for (directory, scope) in directories {
            let files = (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            for file in files where file.pathExtension.lowercased() == "plist" {
                if let item = item(at: file, scope: scope, fileManager: fileManager) {
                    items.append(item)
                }
            }
        }
        return items.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }

    private static func item(at url: URL, scope: BackgroundItem.Scope, fileManager: FileManager) -> BackgroundItem? {
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let settings = plist as? [String: Any]
        else {
            return nil
        }

        let arguments = settings["ProgramArguments"] as? [String]
        let program = (settings["Program"] as? String) ?? arguments?.first

        // "KeepAlive" is either a plain yes/no or a list of conditions; conditions also mean
        // macOS starts the program by itself.
        let keepAlive = (settings["KeepAlive"] as? Bool) ?? (settings["KeepAlive"] != nil)
        let runAtLoad = (settings["RunAtLoad"] as? Bool) ?? false

        // Only a full path can be checked. Anything else is given the benefit of the doubt.
        var programExists = true
        if let program, program.hasPrefix("/") {
            programExists = fileManager.fileExists(atPath: program)
        }

        return BackgroundItem(
            url: url,
            label: (settings["Label"] as? String) ?? url.deletingPathExtension().lastPathComponent,
            program: program,
            scope: scope,
            startsAutomatically: runAtLoad || keepAlive,
            isDisabled: (settings["Disabled"] as? Bool) ?? false,
            programExists: programExists
        )
    }
}
