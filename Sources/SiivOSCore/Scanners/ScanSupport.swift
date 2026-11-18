import Foundation

/// A regular file found while walking the user's folders.
struct WalkedFile {
    let url: URL
    /// Exact length of the file's contents, in bytes.
    let contentBytes: Int64
    /// Space the file takes on disk, in bytes.
    let diskBytes: Int64
    let modified: Date?
}

/// Read-only helpers shared by the scanners.
enum ScanSupport {
    /// The folders in the home folder where people keep their own files.
    static func userFolders(inHome home: URL) -> [URL] {
        ["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
    }

    /// Folders that are really one thing an app looks after, named by their ending:
    /// photo, video and music libraries, catalogues, projects and disk images. macOS
    /// only treats such a folder as a single item while the app that owns it is
    /// installed, so SiivOS knows the endings itself. Taking a file out of one of
    /// these can break the whole library.
    static let libraryEndings: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "aplibrary",
        "lrlibrary", "lrdata", "lrcat-data",
        "fcpbundle", "imovielibrary", "tvlibrary", "musiclibrary", "theater",
        "logicx", "band", "sparsebundle", "backupdb",
        "app", "framework", "bundle", "xcodeproj", "xcworkspace", "playground"
    ]

    /// Every regular file of at least the given size inside the given folders.
    ///
    /// Hidden files are skipped, and so is the inside of packages and libraries such as
    /// apps and photo libraries, which must not be picked apart.
    static func regularFiles(
        in roots: [URL],
        atLeast minimumBytes: Int64,
        fileManager: FileManager
    ) -> [WalkedFile] {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .fileSizeKey,
            .totalFileAllocatedSizeKey,
            .contentModificationDateKey
        ]
        var files: [WalkedFile] = []
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else {
                continue
            }
            for case let url as URL in enumerator {
                if libraryEndings.contains(url.pathExtension.lowercased()),
                   (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.fileSize,
                      Int64(size) >= minimumBytes
                else {
                    continue
                }
                files.append(
                    WalkedFile(
                        url: url,
                        contentBytes: Int64(size),
                        diskBytes: Int64(values.totalFileAllocatedSize ?? size),
                        modified: values.contentModificationDate
                    )
                )
            }
        }
        return files
    }

    /// The items directly inside a folder, with the space each takes on disk.
    /// A folder that does not exist counts as empty. Hidden items are skipped.
    static func children(
        of directory: URL,
        fileManager: FileManager
    ) throws -> [(url: URL, sizeBytes: Int64)] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return contents.map { url in
            (url: url, sizeBytes: FileSize.onDisk(of: url, fileManager: fileManager))
        }
    }

    /// A date written out for people, for example "17 Nov 2026".
    static func describe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
