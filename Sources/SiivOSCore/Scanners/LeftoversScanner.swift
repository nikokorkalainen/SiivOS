import Foundation

/// Finds data left behind in `~/Library` by apps that are no longer installed.
///
/// This scanner is deliberately cautious. It only reports folders that are named after
/// an app identifier such as "com.example.Notes", and only when no installed app comes
/// from the same developer ("com.example"). It will miss some leftovers, which is
/// better than suggesting data that an installed app still uses.
public struct LeftoversScanner: SystemScanner {
    public let id = "leftovers"
    public let title = "Leftovers from removed apps"
    public let summary = "Data in your Library folder that belongs to apps which no longer seem to be installed. SiivOS only lists items when it finds no installed app from the same developer in your Applications folders, so check the list if you keep apps somewhere else."

    /// Folders inside `~/Library` where apps keep data under their identifier, and the
    /// ending that follows the identifier in each.
    private static let locations: [(folder: String, suffix: String)] = [
        ("Application Support", ""),
        ("Containers", ""),
        ("Saved Application State", ".savedState"),
        ("HTTPStorages", ""),
        ("WebKit", ""),
        ("Application Scripts", "")
    ]

    private let libraryDirectory: URL
    private let applicationDirectories: [URL]
    private let minimumBytes: Int64
    private let runningApps: [RunningApp]

    /// - Parameters:
    ///   - applicationDirectories: Where to look for installed apps. Left out, the standard folders are used.
    ///   - minimumBytes: Smaller leftovers are not reported, because removing them frees next to nothing.
    ///   - runningApps: The apps that are open right now. They count as installed wherever they are kept.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        applicationDirectories: [URL]? = nil,
        minimumBytes: Int64 = 1_000_000,
        runningApps: [RunningApp] = []
    ) {
        self.libraryDirectory = homeDirectory.appendingPathComponent("Library", isDirectory: true)
        self.applicationDirectories = applicationDirectories
            ?? InstalledApps.standardDirectories(homeDirectory: homeDirectory)
        self.minimumBytes = minimumBytes
        self.runningApps = runningApps
    }

    public func scan() throws -> [Finding] {
        let fileManager = FileManager.default
        let installed = InstalledApps.find(in: applicationDirectories, fileManager: fileManager)
        var knownDevelopers = Set(installed.compactMap { $0.bundleIdentifier }.compactMap(Self.developer(of:)))
        // If no apps were found at all, something is wrong with the search, and every
        // folder would look like a leftover. Report nothing rather than guess.
        guard !knownDevelopers.isEmpty else {
            return []
        }
        knownDevelopers.formUnion(runningApps.compactMap { $0.bundleIdentifier }.compactMap(Self.developer(of:)))

        var findings: [Finding] = []
        for location in Self.locations {
            let directory = libraryDirectory.appendingPathComponent(location.folder, isDirectory: true)
            // A folder that cannot be read is skipped. macOS protects some of these.
            let children = (try? ScanSupport.children(of: directory, fileManager: fileManager)) ?? []
            for child in children {
                var identifier = child.url.lastPathComponent
                if !location.suffix.isEmpty {
                    guard identifier.hasSuffix(location.suffix) else {
                        continue
                    }
                    identifier.removeLast(location.suffix.count)
                }
                guard Self.looksLikeAppIdentifier(identifier),
                      NeverOffer.category(forItemNamed: identifier) == nil,
                      let developer = Self.developer(of: identifier),
                      !knownDevelopers.contains(developer),
                      child.sizeBytes >= minimumBytes
                else {
                    continue
                }
                findings.append(
                    Finding(
                        url: child.url,
                        sizeBytes: child.sizeBytes,
                        explanation: "Data stored by \(identifier). No installed app from this developer was found."
                    )
                )
            }
        }
        return findings
    }

    /// The developer part of an identifier: "com.example.Notes" gives "com.example".
    static func developer(of identifier: String) -> String? {
        let parts = identifier.lowercased().split(separator: ".")
        guard parts.count >= 2 else {
            return nil
        }
        return "\(parts[0]).\(parts[1])"
    }

    /// True for names shaped like "com.example.Notes": at least three parts separated by
    /// dots, starting with letters, with nothing but letters, digits, hyphens and underscores.
    static func looksLikeAppIdentifier(_ name: String) -> Bool {
        let parts = name.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, let first = parts.first, !first.isEmpty, first.allSatisfy({ $0.isLetter }) else {
            return false
        }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }
}
