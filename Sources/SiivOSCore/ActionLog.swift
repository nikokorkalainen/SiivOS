import Foundation

/// One change SiivOS made, with what it told the user beforehand and what happened to each item since.
public struct ActionRecord: Codable, Equatable, Identifiable, Sendable {
    public enum ItemState: String, Codable, Sendable {
        /// Waiting in the holding area. Can still be put back.
        case held
        /// Put back where it came from.
        case restored
        /// Deleted for good.
        case deleted
    }

    public struct Item: Codable, Equatable, Identifiable, Sendable {
        public let held: HeldItem
        public var state: ItemState

        public var id: UUID { held.id }
    }

    public let id: UUID
    public let date: Date
    /// Short description, for example "Removed 3 items".
    public let title: String
    /// The explanation that was shown before the change ran.
    public let explanation: String
    public var items: [Item]

    /// Combined size of every item in this change, in bytes.
    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.held.sizeBytes }
    }

    /// Combined size of the items still waiting in the holding area, in bytes.
    public var heldBytes: Int64 {
        items.filter { $0.state == .held }.reduce(0) { $0 + $1.held.sizeBytes }
    }

    /// True while at least one item can still be put back.
    public var canUndo: Bool {
        items.contains { $0.state == .held }
    }

    public func count(of state: ItemState) -> Int {
        items.filter { $0.state == state }.count
    }
}

public enum ActionLogError: LocalizedError {
    case unreadable(path: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let path, let reason):
            return tr(
                "The SiivOS history file at %1$@ could not be read (%2$@). Nothing was changed, to avoid losing track of earlier changes.",
                path, reason
            )
        }
    }
}

/// Stores the list of changes as a readable JSON file.
public struct ActionLog {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    /// Reads every recorded change, oldest first. A missing file means nothing has happened yet.
    ///
    /// A damaged file is reported as an error and never treated as empty, because
    /// saving over it would lose the record of what can still be put back.
    public func load() throws -> [ActionRecord] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ActionRecord].self, from: data)
        } catch {
            throw ActionLogError.unreadable(path: fileURL.path, reason: error.localizedDescription)
        }
    }

    public func save(_ records: [ActionRecord]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(records)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}
