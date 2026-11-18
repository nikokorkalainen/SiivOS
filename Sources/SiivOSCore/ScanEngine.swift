import Foundation

/// Something a scanner found that could be removed.
public struct Finding: Equatable, Identifiable, Sendable {
    /// How much care removing an item needs. Every finding carries one of these labels.
    public enum Safety: String, Sendable {
        /// Made by an app or macOS for itself. Removing it loses nothing of the user's.
        case safeToRemove
        /// May be something the user made or still wants. Each one deserves a look.
        case checkFirst

        /// The label as shown to people.
        public var title: String {
            switch self {
            case .safeToRemove: return tr("Safe to remove")
            case .checkFirst: return tr("Check first")
            }
        }
    }

    public let id: UUID
    public let url: URL
    /// Space the item takes on disk, in bytes.
    public let sizeBytes: Int64
    /// Plain-language description of what the item is and why removing it is safe.
    public let explanation: String
    /// Whether the item is safe to remove or should be looked at first.
    public let safety: Safety
    /// One plain sentence on why the item has that label.
    public let safetyReason: String
    /// Set when the item should not be removed right now, for example because the app
    /// it belongs to is open. The item is shown with this reason and cannot be ticked.
    public let heldBackReason: String?
    /// A name to show for the item when its own file name says little, such as
    /// "Xcode build results" for a folder called DerivedData. Left out, the file name is shown.
    public let displayName: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        sizeBytes: Int64,
        explanation: String,
        safety: Safety,
        safetyReason: String,
        heldBackReason: String? = nil,
        displayName: String? = nil
    ) {
        self.id = id
        self.url = url
        self.sizeBytes = sizeBytes
        self.explanation = explanation
        self.safety = safety
        self.safetyReason = safetyReason
        self.heldBackReason = heldBackReason
        self.displayName = displayName
    }
}

/// One kind of check, for example "application caches".
///
/// Scanning only looks. A scanner must never change anything on the Mac; removal
/// always goes through `SafetyCore`.
public protocol SystemScanner: Sendable {
    /// Stable identifier, for example "caches".
    var id: String { get }
    /// Name shown to the user.
    var title: String { get }
    /// One sentence on what this scanner looks for.
    var summary: String { get }

    func scan() throws -> [Finding]
}

/// The combined results of running several scanners.
public struct ScanReport: Sendable {
    public struct Section: Identifiable, Sendable {
        /// The scanner's identifier.
        public let id: String
        public let title: String
        public let summary: String
        /// What the scanner found, largest first.
        public let findings: [Finding]
        /// Why the scanner could not finish, if it failed.
        public let failure: String?

        public var totalBytes: Int64 {
            findings.reduce(0) { $0 + $1.sizeBytes }
        }
    }

    public let sections: [Section]

    public var totalBytes: Int64 {
        sections.reduce(0) { $0 + $1.totalBytes }
    }

    public var findingCount: Int {
        sections.reduce(0) { $0 + $1.findings.count }
    }

    /// Combined size of everything labelled safe to remove that can be removed right
    /// now. Items to check first and items that are held back are left out, and an
    /// item listed under two headings is counted once.
    public var safeToRemoveBytes: Int64 {
        var counted = Set<URL>()
        var total: Int64 = 0
        for section in sections {
            for finding in section.findings
            where finding.safety == .safeToRemove && finding.heldBackReason == nil {
                if counted.insert(finding.url).inserted {
                    total += finding.sizeBytes
                }
            }
        }
        return total
    }

    /// The same report without the findings whose items are no longer where they were,
    /// for use after some of them have been removed. Read-only.
    public func removingFindingsNoLongerOnDisk(fileManager: FileManager = .default) -> ScanReport {
        let remaining = sections.map { section in
            Section(
                id: section.id,
                title: section.title,
                summary: section.summary,
                findings: section.findings.filter { finding in
                    (try? fileManager.attributesOfItem(atPath: finding.url.path)) != nil
                },
                failure: section.failure
            )
        }
        return ScanReport(sections: remaining)
    }
}

/// Runs scanners one after another and collects what they find.
public struct ScanEngine: Sendable {
    public let scanners: [any SystemScanner]

    public init(scanners: [any SystemScanner]) {
        self.scanners = scanners
    }

    /// Runs every scanner. One scanner failing does not stop the others.
    ///
    /// - Parameter progress: Called with each scanner's title just before it starts.
    public func run(progress: ((String) -> Void)? = nil) -> ScanReport {
        let sections = scanners.map { scanner -> ScanReport.Section in
            progress?(scanner.title)
            do {
                let findings = try scanner.scan().sorted { $0.sizeBytes > $1.sizeBytes }
                return ScanReport.Section(
                    id: scanner.id,
                    title: scanner.title,
                    summary: scanner.summary,
                    findings: findings,
                    failure: nil
                )
            } catch {
                return ScanReport.Section(
                    id: scanner.id,
                    title: scanner.title,
                    summary: scanner.summary,
                    findings: [],
                    failure: error.localizedDescription
                )
            }
        }
        return ScanReport(sections: sections)
    }
}

extension ScanEngine {
    /// The scanners behind the Cleanup screen, in the order they are shown.
    ///
    /// - Parameter runningApps: The apps that are open right now. Their data is held back.
    public static func clutter(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        runningApps: [RunningApp] = []
    ) -> ScanEngine {
        ScanEngine(scanners: [
            CachesScanner(homeDirectory: homeDirectory, runningApps: runningApps),
            LogsScanner(homeDirectory: homeDirectory, runningApps: runningApps),
            LeftoversScanner(homeDirectory: homeDirectory, runningApps: runningApps),
            DeveloperClutterScanner(homeDirectory: homeDirectory, runningApps: runningApps),
            OldDownloadsScanner(homeDirectory: homeDirectory),
            LargeFilesScanner(homeDirectory: homeDirectory),
            DuplicateFilesScanner(homeDirectory: homeDirectory)
        ])
    }
}
