import Foundation

/// Decides which items SiivOS must never remove, whatever asked for it.
///
/// These rules are the last line of defence. Scanners should only suggest sensible
/// items in the first place, but every removal is checked here as well.
public struct SafetyRules: Sendable {
    public let homeDirectory: URL
    public let holdingDirectory: URL

    public init(homeDirectory: URL, holdingDirectory: URL) {
        self.homeDirectory = homeDirectory
        self.holdingDirectory = holdingDirectory
    }

    /// Folders directly inside the home folder that must stay where they are.
    private static let mainHomeFolders: Set<String> = [
        "applications", "desktop", "documents", "downloads", "library",
        "movies", "music", "pictures", "public", ".trash"
    ]

    /// Folders in the Library whose contents can never be replaced once lost.
    private static let irreplaceableLibraryFolders: Set<String> = ["keychains", "mail", "messages"]

    /// Top-level folders that belong to macOS itself.
    private static let systemFolders: Set<String> = ["system", "bin", "sbin", "etc", "dev"]

    /// A plain-language reason why the item must be left alone, or `nil` when it may be removed.
    public func reasonToRefuse(_ url: URL) -> String? {
        let item = Self.location(of: url)

        if item.count <= 2 {
            return "It is one of the top-level folders of the disk."
        }
        if Self.systemFolders.contains(item[1]) {
            return "It is part of macOS."
        }
        if item[1] == "usr" && !(item.count > 3 && item[2] == "local") {
            return "It is part of macOS."
        }

        let home = Self.components(of: homeDirectory.standardizedFileURL.resolvingSymlinksInPath())
        if item == home {
            return "It is your home folder."
        }
        if home.starts(with: item) {
            return "It contains your home folder."
        }
        if item.starts(with: home) {
            let inside = Array(item.dropFirst(home.count))
            if inside.count == 1, Self.mainHomeFolders.contains(inside[0]) {
                return "It is one of the main folders in your home folder."
            }
            if inside.count > 2, inside[0] == "library", Self.irreplaceableLibraryFolders.contains(inside[1]) {
                return "It is part of your saved passwords, mail or messages, which cannot be replaced."
            }
            if inside.count == 2, inside[0] == "library" {
                return "macOS and your apps rely on this folder. Only items inside it can be removed."
            }
        }

        let holding = Self.components(of: holdingDirectory.standardizedFileURL.resolvingSymlinksInPath())
        if item.starts(with: holding) {
            return "It is already in the SiivOS holding area."
        }
        if holding.starts(with: item) {
            return "It contains SiivOS's own data, including the holding area."
        }

        return nil
    }

    /// Where an item really lives: links in the folders above it are followed,
    /// but the item itself is not, so a link is judged by where the link is.
    private static func location(of url: URL) -> [String] {
        let standardized = url.standardizedFileURL
        if standardized.path == "/" {
            return ["/"]
        }
        let parent = standardized.deletingLastPathComponent().resolvingSymlinksInPath()
        return components(of: parent.appendingPathComponent(standardized.lastPathComponent))
    }

    /// The parts of a path, lowercased because Mac disks normally ignore case.
    /// "/Users/niko" becomes ["/", "users", "niko"].
    ///
    /// On a Mac, /var, /tmp and /etc are other names for /private/var, /private/tmp and
    /// /private/etc. Both spellings are reduced to the short one so they always compare equal.
    private static func components(of url: URL) -> [String] {
        var parts = url.path.split(separator: "/").map { $0.lowercased() }
        if parts.count >= 2, parts[0] == "private", ["var", "tmp", "etc"].contains(parts[1]) {
            parts.removeFirst()
        }
        return ["/"] + parts
    }
}
