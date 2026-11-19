import Foundation

/// Measures how much disk space files and folders take up. Read-only.
enum FileSize {
    private static let sizeKeys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey
    ]

    /// Space used on disk by a file, or by a folder and everything inside it, in bytes.
    ///
    /// Items that cannot be read are counted as zero. A symbolic link counts as the
    /// link itself, never as the thing it points to.
    static func onDisk(of url: URL, fileManager: FileManager = .default) -> Int64 {
        var total = ownSize(of: url)

        let kind = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard kind?.isDirectory == true, kind?.isSymbolicLink != true else {
            return total
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: sizeKeys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return total
        }
        for case let child as URL in enumerator {
            total += ownSize(of: child)
        }
        return total
    }

    /// Space used by the item itself, not counting anything inside it.
    static func ownSize(of url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: Set(sizeKeys)) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }
}
