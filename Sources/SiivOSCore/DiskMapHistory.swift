import Foundation

/// The sizes found at one measuring of the home folder, kept so that a later measuring
/// can say what has grown. It holds names and sizes only, and stays on this Mac.
public struct DiskMapSnapshot: Codable, Equatable, Sendable {
    /// How an item compares with an earlier measuring.
    public enum Change: Equatable, Sendable {
        /// Larger by this many bytes, or smaller when the number is negative.
        case changed(Int64)
        /// It was not there at the earlier measuring.
        case new
    }

    public let date: Date
    /// Size in bytes by path: the folder that was measured, the items in it, and the
    /// largest items in each of those that was looked into.
    public let sizes: [String: Int64]
    /// Paths of the folders whose every item is in `sizes`. In such a folder an item
    /// that is missing was not there; in any other it may only have been too small to
    /// be noted down.
    public let completeFolders: [String]

    public init(date: Date, sizes: [String: Int64], completeFolders: [String]) {
        self.date = date
        self.sizes = sizes
        self.completeFolders = completeFolders
    }

    /// Notes down a measuring: the folder, everything directly in it that the measuring
    /// kept, and the largest items of each folder in it that was looked into.
    public init(of folder: DiskMapNode, date: Date = Date()) {
        var sizes = [folder.url.path: folder.sizeBytes]
        var complete: [String] = []

        let items = folder.children + folder.smallerItems
        if folder.smallerItems.count == folder.otherCount {
            complete.append(folder.url.path)
        }
        for item in items {
            sizes[item.url.path] = item.sizeBytes
            guard item.isOpened else {
                continue
            }
            for inner in item.children {
                sizes[inner.url.path] = inner.sizeBytes
            }
            if item.otherCount == 0 {
                complete.append(item.url.path)
            }
        }

        // Whole seconds, so that a date survives being saved and read back unchanged.
        self.date = Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
        self.sizes = sizes
        self.completeFolders = complete.sorted()
    }

    /// How an item in a folder compares with this earlier measuring, or `nil` when that
    /// cannot be told: it was too small to be noted down then, or macOS showed nothing
    /// of it then, so that its size now says nothing about growth.
    public func change(of item: DiskMapNode, in folder: DiskMapNode) -> Change? {
        if let before = sizes[item.url.path] {
            guard before > 0 else {
                return nil
            }
            return .changed(item.sizeBytes - before)
        }
        return completeFolders.contains(folder.url.path) ? .new : nil
    }

    /// By how many bytes the folder itself is larger than at this earlier measuring,
    /// negative when smaller, or `nil` when it was not noted down then.
    public func change(of folder: DiskMapNode) -> Int64? {
        guard let before = sizes[folder.url.path], before > 0 else {
            return nil
        }
        return folder.sizeBytes - before
    }
}

/// The measurings SiivOS remembers, oldest first.
public struct DiskMapHistory: Codable, Equatable, Sendable {
    public var snapshots: [DiskMapSnapshot]

    /// How many measurings are kept.
    static let kept = 8
    /// A measuring this old is one to compare with. Younger ones are from the same
    /// sitting, more or less.
    static let settledAfter: TimeInterval = 12 * 3_600
    /// Changes smaller than this are not worth pointing out.
    public static let changeWorthShowing: Int64 = 100_000_000

    public init(snapshots: [DiskMapSnapshot] = []) {
        self.snapshots = snapshots
    }

    /// The measuring to compare a new one with: the newest that is at least half a day
    /// old, or failing that the oldest there is. `nil` before the first measuring.
    public func baseline(now: Date = Date()) -> DiskMapSnapshot? {
        snapshots.last { now.timeIntervalSince($0.date) >= Self.settledAfter } ?? snapshots.first
    }

    /// Adds a measuring. One taken soon after the last replaces it, as long as an older
    /// one remains to compare with, so that measuring several times in one sitting does
    /// not push the older ones out.
    public mutating func add(_ snapshot: DiskMapSnapshot) {
        if snapshots.count >= 2,
           let last = snapshots.last,
           snapshot.date.timeIntervalSince(last.date) < Self.settledAfter {
            snapshots[snapshots.count - 1] = snapshot
        } else {
            snapshots.append(snapshot)
        }
        snapshots = Array(snapshots.suffix(Self.kept))
    }
}

/// Keeps the remembered measurings in a file next to SiivOS's other data.
public struct DiskMapHistoryStore: Sendable {
    public let fileURL: URL

    public init(dataDirectory: URL) {
        fileURL = dataDirectory.appendingPathComponent("disk-map-history.json")
    }

    public static func standard() -> DiskMapHistoryStore {
        DiskMapHistoryStore(dataDirectory: SiivOSData.standardDirectory())
    }

    /// The remembered measurings. A missing or unreadable file gives none: the Disk Map
    /// then simply has nothing to compare with until it has been measured again.
    public func load() -> DiskMapHistory {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? decoder.decode(DiskMapHistory.self, from: data)
        else {
            return DiskMapHistory()
        }
        return history
    }

    public func save(_ history: DiskMapHistory) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(history)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
