import Foundation

/// Finds the caches apps keep in `~/Library/Caches`.
public struct CachesScanner: SystemScanner {
    public let id = "caches"
    public var title: String { tr("App caches") }
    public var summary: String {
        tr("Temporary files apps keep so they can work faster. Apps create them again when needed, so an app may start a little slower the first time afterwards. Quit an app before removing its cache.")
    }

    private let directory: URL
    private let minimumBytes: Int64
    private let runningApps: [RunningApp]

    /// - Parameters:
    ///   - minimumBytes: Smaller caches are not reported, because removing them frees next to nothing.
    ///   - runningApps: The apps that are open right now. Their caches are listed but held back.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 1_000_000,
        runningApps: [RunningApp] = []
    ) {
        self.directory = homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        self.minimumBytes = minimumBytes
        self.runningApps = runningApps
    }

    public func scan() throws -> [Finding] {
        try ScanSupport.children(of: directory, fileManager: .default)
            .filter { NeverOffer.category(forItemNamed: $0.url.lastPathComponent) == nil }
            .filter { $0.sizeBytes >= minimumBytes }
            .map { child in
                let name = child.url.lastPathComponent
                let openApp = RunningApp.using(itemNamed: name, among: runningApps)
                return Finding(
                    url: child.url,
                    sizeBytes: child.sizeBytes,
                    explanation: tr("Cached data for %1$@.", name),
                    heldBackReason: openApp.map { tr("%1$@ is open. Quit it, then scan again to clean its cache.", $0.name) }
                )
            }
    }
}

/// Finds the log files apps write to `~/Library/Logs`.
public struct LogsScanner: SystemScanner {
    public let id = "logs"
    public var title: String { tr("Logs") }
    public var summary: String {
        tr("Notes apps write about what they were doing, mainly useful for tracking down problems. Removing them does not change how apps work.")
    }

    private let directory: URL
    private let minimumBytes: Int64
    private let runningApps: [RunningApp]

    /// - Parameters:
    ///   - minimumBytes: Smaller logs are not reported, because removing them frees next to nothing.
    ///   - runningApps: The apps that are open right now. Their logs are listed but held back.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 1_000_000,
        runningApps: [RunningApp] = []
    ) {
        self.directory = homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true)
        self.minimumBytes = minimumBytes
        self.runningApps = runningApps
    }

    public func scan() throws -> [Finding] {
        try ScanSupport.children(of: directory, fileManager: .default)
            .filter { NeverOffer.category(forItemNamed: $0.url.lastPathComponent) == nil }
            .filter { $0.sizeBytes >= minimumBytes }
            .map { child in
                let name = child.url.lastPathComponent
                let openApp = RunningApp.using(itemNamed: name, among: runningApps)
                return Finding(
                    url: child.url,
                    sizeBytes: child.sizeBytes,
                    explanation: tr("Logs from %1$@.", name),
                    heldBackReason: openApp.map { tr("%1$@ is open. Quit it, then scan again to remove its logs.", $0.name) }
                )
            }
    }
}
