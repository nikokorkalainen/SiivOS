import Foundation

/// Finds items in the Downloads folder that have not been touched for a long time.
public struct OldDownloadsScanner: SystemScanner {
    public let id = "old-downloads"
    public var title: String { tr("Old downloads") }
    public var summary: String {
        tr(
            "Items in your Downloads folder that have not been opened or changed for more than %1$@ days.",
            "\(olderThanDays)"
        )
    }

    private let directory: URL
    private let olderThanDays: Int
    private let now: Date

    /// - Parameters:
    ///   - olderThanDays: How long an item must have been left untouched to be reported.
    ///   - now: The date to measure from. Tests pass their own.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        olderThanDays: Int = 90,
        now: Date = Date()
    ) {
        self.directory = homeDirectory.appendingPathComponent("Downloads", isDirectory: true)
        self.olderThanDays = olderThanDays
        self.now = now
    }

    /// Why the user's own files are always to be checked first.
    static var ownFileReason: String {
        tr("This is your own file. Only you know whether you still need it.")
    }

    public func scan() throws -> [Finding] {
        let cutoff = now.addingTimeInterval(-Double(olderThanDays) * 86_400)
        return try ScanSupport.children(of: directory, fileManager: .default).compactMap { child in
            guard let lastTouched = Self.lastTouched(child.url), lastTouched < cutoff else {
                return nil
            }
            return Finding(
                url: child.url,
                sizeBytes: child.sizeBytes,
                explanation: tr("Not opened or changed since %1$@.", ScanSupport.describe(lastTouched)),
                safety: .checkFirst,
                safetyReason: Self.ownFileReason
            )
        }
    }

    /// The most recent moment the item was added, changed or read, as far as the disk records it.
    private static func lastTouched(_ url: URL) -> Date? {
        #if os(macOS)
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey, .contentAccessDateKey, .addedToDirectoryDateKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        let dates = [values.contentModificationDate, values.contentAccessDate, values.addedToDirectoryDate]
        #else
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .contentAccessDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else {
            return nil
        }
        let dates = [values.contentModificationDate, values.contentAccessDate]
        #endif
        return dates.compactMap { $0 }.max()
    }
}

/// Finds big files in the folders where people keep their own files.
public struct LargeFilesScanner: SystemScanner {
    public let id = "large-files"
    public var title: String { tr("Large files") }
    public var summary: String {
        tr(
            "Files of %1$@ or more in your Desktop, Documents, Downloads, Movies, Music and Pictures folders.",
            ByteCountFormatter.string(fromByteCount: minimumBytes, countStyle: .file)
        )
    }

    private let roots: [URL]
    private let minimumBytes: Int64
    private let foldersLeftOut: [URL]

    /// - Parameter foldersLeftOut: Folders that are not looked into at all.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 100_000_000,
        foldersLeftOut: [URL] = []
    ) {
        self.roots = ScanSupport.userFolders(inHome: homeDirectory)
        self.minimumBytes = minimumBytes
        self.foldersLeftOut = foldersLeftOut
    }

    public func scan() throws -> [Finding] {
        ScanSupport.regularFiles(in: roots, atLeast: minimumBytes, leavingOut: foldersLeftOut, fileManager: .default).map { file in
            let changed = file.modified.map { tr("Last changed %1$@.", ScanSupport.describe($0)) } ?? tr("A large file.")
            return Finding(
                url: file.url,
                sizeBytes: file.diskBytes,
                explanation: changed,
                safety: .checkFirst,
                safetyReason: OldDownloadsScanner.ownFileReason
            )
        }
    }
}

/// Finds files whose contents are exactly the same as another file's.
public struct DuplicateFilesScanner: SystemScanner {
    public let id = "duplicates"
    public var title: String { tr("Duplicate files") }
    public var summary: String {
        tr("Extra copies of files with exactly the same contents, in your Desktop, Documents, Downloads, Movies, Music and Pictures folders. One copy of each is always kept and is not listed here. macOS stores some copies only once; such a copy is listed, but counted as freeing nothing.")
    }

    private let roots: [URL]
    private let minimumBytes: Int64
    private let foldersLeftOut: [URL]
    private let sharesSpace: @Sendable (URL) -> Bool

    /// - Parameters:
    ///   - minimumBytes: Smaller files are not compared, to keep the scan quick.
    ///   - foldersLeftOut: Folders that are not looked into at all. A file with a copy in
    ///     such a folder is not a duplicate as far as this scanner can see.
    ///   - sharesSpace: Says whether a file shares its disk space with another file.
    ///     Left out, macOS is asked. Tests pass their own.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 1_000_000,
        foldersLeftOut: [URL] = [],
        sharesSpace: @escaping @Sendable (URL) -> Bool = { DuplicateFilesScanner.sharesDiskSpace($0) }
    ) {
        self.roots = ScanSupport.userFolders(inHome: homeDirectory)
        self.minimumBytes = minimumBytes
        self.foldersLeftOut = foldersLeftOut
        self.sharesSpace = sharesSpace
    }

    /// True when macOS says the file shares its space on disk with another file.
    ///
    /// When a file is copied on a Mac, the disk usually keeps the contents once and lets
    /// both files point at them, until one of them is changed. Removing one of two such
    /// files frees next to nothing. macOS calls this a hint, so SiivOS words what it
    /// shows with care. Only reads.
    public static func sharesDiskSpace(_ url: URL) -> Bool {
        #if os(macOS)
        return (try? url.resourceValues(forKeys: [.mayShareFileContentKey]))?.mayShareFileContent ?? false
        #else
        return false
        #endif
    }

    public func scan() throws -> [Finding] {
        let fileManager = FileManager.default
        let files = ScanSupport.regularFiles(in: roots, atLeast: minimumBytes, leavingOut: foldersLeftOut, fileManager: fileManager)

        var findings: [Finding] = []
        // Files can only be identical if they are the same length, so compare within each length.
        for sameLength in Dictionary(grouping: files, by: { $0.contentBytes }).values where sameLength.count > 1 {
            // Then within each group whose first part matches, which rules most files out cheaply.
            let sameStart = Dictionary(grouping: sameLength, by: { Self.firstBytes(of: $0.url) })
            for (start, candidates) in sameStart where start != nil && candidates.count > 1 {
                for group in Self.groupsOfIdenticalFiles(candidates, fileManager: fileManager) {
                    let kept = group[0]
                    // Copies that share their disk space take it up only once between
                    // them. If the kept copy is one of them, that space stays in use
                    // whatever is removed. If not, it is counted for the first of them.
                    let keptShares = sharesSpace(kept.url)
                    var sharedSpaceIsCounted = keptShares
                    for extra in group.dropFirst() {
                        var frees = extra.diskBytes
                        var explanation = tr("Identical to %1$@, which is kept.", kept.url.path)
                        if sharesSpace(extra.url) {
                            if sharedSpaceIsCounted {
                                frees = 0
                            }
                            sharedSpaceIsCounted = true
                            explanation = keptShares
                                ? tr("Identical to %1$@, which is kept. The two share their disk space, so removing this copy frees next to nothing.", kept.url.path)
                                : tr("Identical to %1$@, which is kept. It shares its disk space with another copy, so removing it alone may free nothing.", kept.url.path)
                        }
                        findings.append(
                            Finding(
                                url: extra.url,
                                sizeBytes: extra.diskBytes,
                                explanation: explanation,
                                safety: .checkFirst,
                                safetyReason: tr("An exact copy of another file, but it may sit where you or an app expect to find it."),
                                freesBytes: frees
                            )
                        )
                    }
                }
            }
        }
        return findings
    }

    /// The start of a file, or `nil` when it cannot be read.
    private static func firstBytes(of url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }
        defer { try? handle.close() }
        return try? handle.read(upToCount: 65_536)
    }

    /// Sorts files into groups with exactly the same contents. Only groups of two or more are
    /// returned, each ordered so that the copy to keep comes first.
    private static func groupsOfIdenticalFiles(
        _ candidates: [WalkedFile],
        fileManager: FileManager
    ) -> [[WalkedFile]] {
        // Prefer keeping the copy with the shortest path: copies tend to have longer names
        // ("report copy.pdf") or sit deeper in folders.
        let ordered = candidates.sorted { first, second in
            if first.url.path.count != second.url.path.count {
                return first.url.path.count < second.url.path.count
            }
            return first.url.path < second.url.path
        }

        var groups: [[WalkedFile]] = []
        var identities: [[FileIdentity?]] = []
        for file in ordered {
            let identity = FileIdentity(of: file.url, fileManager: fileManager)
            var placed = false
            for index in groups.indices {
                // Two names for one and the same file are not copies: removing one frees nothing.
                if let identity, identities[index].contains(identity) {
                    placed = true
                    break
                }
                if fileManager.contentsEqual(atPath: groups[index][0].url.path, andPath: file.url.path) {
                    groups[index].append(file)
                    identities[index].append(identity)
                    placed = true
                    break
                }
            }
            if !placed {
                groups.append([file])
                identities.append([identity])
            }
        }
        return groups.filter { $0.count > 1 }
    }
}

/// Identifies a file on disk regardless of its name, so that two names for the same
/// file (a "hard link") can be told apart from two separate copies.
private struct FileIdentity: Equatable {
    let volume: UInt64
    let file: UInt64

    init?(of url: URL, fileManager: FileManager) {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let volume = (attributes[.systemNumber] as? NSNumber)?.uint64Value,
              let file = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        else {
            return nil
        }
        self.volume = volume
        self.file = file
    }
}
