import Foundation

/// An item that was moved out of its original place into the holding area.
public struct HeldItem: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Full path the item had before it was moved.
    public let originalPath: String
    /// Space the item took on disk when it was moved, in bytes.
    public let sizeBytes: Int64

    public var originalURL: URL {
        URL(fileURLWithPath: originalPath)
    }

    /// File or folder name, without the path.
    public var name: String {
        originalURL.lastPathComponent
    }
}

public enum HoldingAreaError: LocalizedError, Equatable {
    case itemMissing(String)
    case heldCopyMissing(String)
    case originalLocationOccupied(String)

    public var errorDescription: String? {
        switch self {
        case .itemMissing(let path):
            return "\(path) no longer exists, so it could not be moved."
        case .heldCopyMissing(let path):
            return "The held copy of \(path) is missing from the holding area."
        case .originalLocationOccupied(let path):
            return "Something else now exists at \(path). Move or rename it, then try again."
        }
    }
}

/// A folder where removed items wait, so that removing something is never final by itself.
///
/// Each held item gets its own subfolder named after the item's identifier, which keeps
/// items with the same name apart.
public struct HoldingArea {
    public let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    /// Where a held item is stored inside the holding area.
    public func heldURL(for item: HeldItem) -> URL {
        container(for: item).appendingPathComponent(item.name)
    }

    /// Whether the held copy of an item is still in the holding area.
    public func contains(_ item: HeldItem) -> Bool {
        exists(heldURL(for: item))
    }

    /// Moves a file or folder into the holding area.
    public func hold(_ url: URL) throws -> HeldItem {
        let source = url.standardizedFileURL
        guard exists(source) else {
            throw HoldingAreaError.itemMissing(source.path)
        }

        let item = HeldItem(
            id: UUID(),
            originalPath: source.path,
            sizeBytes: FileSize.onDisk(of: source, fileManager: fileManager)
        )
        let folder = container(for: item)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: source, to: heldURL(for: item))
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
        return item
    }

    /// Moves a held item back to where it came from.
    ///
    /// Refuses when something else has taken its place, so nothing is ever overwritten.
    public func restore(_ item: HeldItem) throws {
        let held = heldURL(for: item)
        guard exists(held) else {
            throw HoldingAreaError.heldCopyMissing(item.originalPath)
        }
        let original = item.originalURL
        guard !exists(original) else {
            throw HoldingAreaError.originalLocationOccupied(item.originalPath)
        }

        try fileManager.createDirectory(
            at: original.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: held, to: original)
        try? fileManager.removeItem(at: container(for: item))
    }

    /// Deletes a held item for good. This cannot be undone.
    public func deletePermanently(_ item: HeldItem) throws {
        let folder = container(for: item)
        guard exists(folder) else {
            return
        }
        try fileManager.removeItem(at: folder)
    }

    private func container(for item: HeldItem) -> URL {
        directory.appendingPathComponent(item.id.uuidString, isDirectory: true)
    }

    /// True when something exists at the URL. A link counts even if its target is gone.
    private func exists(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }
}
