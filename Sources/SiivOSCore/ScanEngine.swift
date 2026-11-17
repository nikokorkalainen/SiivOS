import Foundation

/// Something a scanner found that could be removed.
public struct Finding: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let url: URL
    /// Space the item takes on disk, in bytes.
    public let sizeBytes: Int64
    /// Plain-language description of what the item is and why removing it is safe.
    public let explanation: String

    public init(id: UUID = UUID(), url: URL, sizeBytes: Int64, explanation: String) {
        self.id = id
        self.url = url
        self.sizeBytes = sizeBytes
        self.explanation = explanation
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
}

/// Runs scanners one after another and collects what they find.
public struct ScanEngine: Sendable {
    public let scanners: [any SystemScanner]

    public init(scanners: [any SystemScanner]) {
        self.scanners = scanners
    }

    /// Runs every scanner. One scanner failing does not stop the others.
    public func run() -> ScanReport {
        let sections = scanners.map { scanner -> ScanReport.Section in
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
