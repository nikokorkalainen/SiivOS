import Foundation

/// A folder or file with the space it takes, and for a folder that has been looked
/// into, the largest things inside it.
public struct DiskMapNode: Equatable, Identifiable, Sendable {
    public let url: URL
    /// The name as Finder shows it.
    public let name: String
    /// Space taken on disk, including everything inside, in bytes.
    public let sizeBytes: Int64
    /// True for a plain folder that can be looked into. False for files, and for apps,
    /// photo libraries and the like, which are one thing and are never picked apart.
    public let canBeOpened: Bool
    /// True when the folder has been looked into, so `children` says what is in it.
    public let isOpened: Bool
    /// The largest things inside, largest first.
    public let children: [DiskMapNode]
    /// The combined size of everything inside that is too small to be listed.
    public let otherBytes: Int64
    /// How many things that is.
    public let otherCount: Int

    public var id: URL { url }

    public init(
        url: URL,
        name: String,
        sizeBytes: Int64,
        canBeOpened: Bool,
        isOpened: Bool = false,
        children: [DiskMapNode] = [],
        otherBytes: Int64 = 0,
        otherCount: Int = 0
    ) {
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.canBeOpened = canBeOpened
        self.isOpened = isOpened
        self.children = children
        self.otherBytes = otherBytes
        self.otherCount = otherCount
    }
}

/// Measures where the space in a folder goes. Only reads; never changes anything.
public enum DiskMap {
    /// How many of a folder's largest items are listed. The rest are added up.
    public static let largestListed = 24

    /// Measures a folder and what is inside it.
    ///
    /// - Parameters:
    ///   - levels: How many levels of folders are looked into: 1 lists what is directly
    ///     in the folder, 2 also what is in each of those folders. Deeper folders are
    ///     measured as a whole, and can be looked into later by measuring them.
    ///   - isCancelled: Asked now and then; when it says yes, measuring stops early and
    ///     what was measured so far is returned.
    ///   - progress: Called with the name of each item directly in the folder, just
    ///     before it is measured.
    public static func measure(
        _ folder: URL,
        levels: Int = 2,
        fileManager: FileManager = .default,
        isCancelled: () -> Bool = { false },
        progress: ((String) -> Void)? = nil
    ) -> DiskMapNode {
        open(folder.standardizedFileURL, levels: max(1, levels), fileManager: fileManager, isCancelled: isCancelled, progress: progress)
    }

    private static func open(
        _ folder: URL,
        levels: Int,
        fileManager: FileManager,
        isCancelled: () -> Bool,
        progress: ((String) -> Void)?
    ) -> DiskMapNode {
        let contents = (try? fileManager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )) ?? []

        var nodes: [DiskMapNode] = []
        for item in contents {
            if isCancelled() {
                break
            }
            let name = fileManager.displayName(atPath: item.path)
            progress?(name)

            let kind = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            // A link counts as the link itself, never as what it points to.
            let isFolder = kind?.isDirectory == true && kind?.isSymbolicLink != true
            let canBeOpened = isFolder && !isOneThing(item)

            if canBeOpened, levels > 1 {
                // Only the top level reports progress; deeper names would flash by.
                nodes.append(open(item, levels: levels - 1, fileManager: fileManager, isCancelled: isCancelled, progress: nil))
            } else {
                nodes.append(
                    DiskMapNode(
                        url: item,
                        name: name,
                        sizeBytes: FileSize.onDisk(of: item, fileManager: fileManager),
                        canBeOpened: canBeOpened
                    )
                )
            }
        }

        nodes.sort { first, second in
            if first.sizeBytes != second.sizeBytes {
                return first.sizeBytes > second.sizeBytes
            }
            return first.name < second.name
        }
        let listed = Array(nodes.prefix(largestListed))
        let others = nodes.dropFirst(largestListed)
        let total = nodes.reduce(FileSize.ownSize(of: folder)) { $0 + $1.sizeBytes }

        return DiskMapNode(
            url: folder,
            name: fileManager.displayName(atPath: folder.path),
            sizeBytes: total,
            canBeOpened: true,
            isOpened: true,
            children: listed,
            otherBytes: others.reduce(0) { $0 + $1.sizeBytes },
            otherCount: others.count
        )
    }

    /// True for folders that are really one thing: apps and other packages, and photo,
    /// video and music libraries. They are measured, but never looked into.
    static func isOneThing(_ folder: URL) -> Bool {
        if ScanSupport.libraryEndings.contains(folder.pathExtension.lowercased()) {
            return true
        }
        #if os(macOS)
        return (try? folder.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
        #else
        return false
        #endif
    }
}

/// A rectangle in a map, measured from the top left corner.
public struct MapRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var area: Double { width * height }
}

/// Lays sizes out as rectangles that fill an area, each as large as its share, and each
/// as close to a square as the others allow. Squarish blocks are easier to compare by
/// eye than long thin strips.
public enum Treemap {
    /// - Parameter sizes: One size for each block. Sizes of zero or less get an empty block.
    /// - Returns: One rectangle for each size, in the order the sizes were given.
    public static func layout(sizes: [Double], width: Double, height: Double) -> [MapRect] {
        var result = Array(repeating: MapRect(x: 0, y: 0, width: 0, height: 0), count: sizes.count)
        let total = sizes.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, width > 0, height > 0 else {
            return result
        }
        // Largest first: the method gives its best shapes that way.
        let order = sizes.indices.filter { sizes[$0] > 0 }.sorted { sizes[$0] > sizes[$1] }
        let scale = width * height / total

        var free = MapRect(x: 0, y: 0, width: width, height: height)
        var row: [Int] = []
        var rowArea = 0.0

        func worstShape(_ areas: [Double], sum: Double, side: Double) -> Double {
            guard let largest = areas.max(), let smallest = areas.min(), sum > 0, side > 0, smallest > 0 else {
                return Double.infinity
            }
            let sideSquared = side * side
            return max(sideSquared * largest / (sum * sum), sum * sum / (sideSquared * smallest))
        }

        func placeRow() {
            guard !row.isEmpty, rowArea > 0 else {
                return
            }
            if free.width >= free.height {
                // A column down the left edge of what is free.
                let columnWidth = free.height > 0 ? rowArea / free.height : 0
                var y = free.y
                for index in row {
                    let blockHeight = columnWidth > 0 ? sizes[index] * scale / columnWidth : 0
                    result[index] = MapRect(x: free.x, y: y, width: columnWidth, height: blockHeight)
                    y += blockHeight
                }
                free.x += columnWidth
                free.width = max(0, free.width - columnWidth)
            } else {
                // A row along the top edge of what is free.
                let rowHeight = free.width > 0 ? rowArea / free.width : 0
                var x = free.x
                for index in row {
                    let blockWidth = rowHeight > 0 ? sizes[index] * scale / rowHeight : 0
                    result[index] = MapRect(x: x, y: free.y, width: blockWidth, height: rowHeight)
                    x += blockWidth
                }
                free.y += rowHeight
                free.height = max(0, free.height - rowHeight)
            }
            row = []
            rowArea = 0
        }

        for index in order {
            let area = sizes[index] * scale
            let side = min(free.width, free.height)
            let current = row.map { sizes[$0] * scale }
            if row.isEmpty || worstShape(current + [area], sum: rowArea + area, side: side) <= worstShape(current, sum: rowArea, side: side) {
                row.append(index)
                rowArea += area
            } else {
                placeRow()
                row = [index]
                rowArea = area
            }
        }
        placeRow()
        return result
    }
}
