import Foundation

/// Finds the caches apps keep in `~/Library/Caches`.
public struct CachesScanner: SystemScanner {
    public let id = "caches"
    public let title = "App caches"
    public let summary = "Temporary files apps keep so they can work faster. Apps create them again when needed, so an app may start a little slower the first time afterwards. Quit an app before removing its cache."

    private let directory: URL
    private let minimumBytes: Int64

    /// - Parameter minimumBytes: Smaller caches are not reported, because removing them frees next to nothing.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 1_000_000
    ) {
        self.directory = homeDirectory.appendingPathComponent("Library/Caches", isDirectory: true)
        self.minimumBytes = minimumBytes
    }

    public func scan() throws -> [Finding] {
        try ScanSupport.children(of: directory, fileManager: .default)
            // Caches that belong to macOS itself are left to macOS.
            .filter { !$0.url.lastPathComponent.lowercased().hasPrefix("com.apple.") }
            .filter { $0.sizeBytes >= minimumBytes }
            .map { child in
                Finding(
                    url: child.url,
                    sizeBytes: child.sizeBytes,
                    explanation: "Cached data for \(child.url.lastPathComponent)."
                )
            }
    }
}

/// Finds the log files apps write to `~/Library/Logs`.
public struct LogsScanner: SystemScanner {
    public let id = "logs"
    public let title = "Logs"
    public let summary = "Notes apps write about what they were doing, mainly useful for tracking down problems. Removing them does not change how apps work."

    private let directory: URL
    private let minimumBytes: Int64

    /// - Parameter minimumBytes: Smaller logs are not reported, because removing them frees next to nothing.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 1_000_000
    ) {
        self.directory = homeDirectory.appendingPathComponent("Library/Logs", isDirectory: true)
        self.minimumBytes = minimumBytes
    }

    public func scan() throws -> [Finding] {
        try ScanSupport.children(of: directory, fileManager: .default)
            .filter { $0.sizeBytes >= minimumBytes }
            .map { child in
                Finding(
                    url: child.url,
                    sizeBytes: child.sizeBytes,
                    explanation: "Logs from \(child.url.lastPathComponent)."
                )
            }
    }
}
