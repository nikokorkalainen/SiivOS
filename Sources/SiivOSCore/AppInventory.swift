import Foundation

/// An installed app together with the facts the Apps screen shows about it.
public struct AppInfo: Equatable, Identifiable, Sendable {
    public let app: InstalledApp
    /// Space the app itself takes on disk, in bytes. Its stored data is not included.
    public let sizeBytes: Int64
    /// When the app was last opened, if macOS has a record of it.
    public let lastUsed: Date?
    /// True for apps that are part of macOS and cannot be uninstalled.
    public let isPartOfMacOS: Bool

    public var id: URL { app.url }
}

/// Lists the installed apps with their size and last use. Read-only.
public enum AppInventory {
    /// Measures every app in the given folders. This reads every file inside every app,
    /// so it can take a while.
    ///
    /// - Parameter progress: Called with each app's name just before it is measured.
    public static func load(
        directories: [URL] = InstalledApps.standardDirectories(),
        fileManager: FileManager = .default,
        progress: ((String) -> Void)? = nil
    ) -> [AppInfo] {
        InstalledApps.find(in: directories, fileManager: fileManager).map { app in
            progress?(app.name)
            return AppInfo(
                app: app,
                sizeBytes: FileSize.onDisk(of: app.url, fileManager: fileManager),
                lastUsed: lastUsed(app.url),
                isPartOfMacOS: app.url.standardizedFileURL.path.hasPrefix("/System/")
            )
        }
    }

    /// When Spotlight last saw the app being opened. Unknown when Spotlight has no record.
    private static func lastUsed(_ url: URL) -> Date? {
        #if os(macOS)
        return NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
        #else
        return nil
        #endif
    }
}
