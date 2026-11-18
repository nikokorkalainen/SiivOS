import Foundation

/// What macOS lets SiivOS see. Only reads; asking never brings up a permission question.
public enum Permissions {
    /// True when SiivOS has Full Disk Access, the one permission that covers every
    /// folder at once, so macOS stops asking folder by folder.
    ///
    /// macOS offers no direct way to ask, so this tries to open a file that only apps
    /// with Full Disk Access may read: the user's own list of app permissions. Without
    /// the permission the attempt simply fails; nothing is shown and nothing changes.
    public static func hasFullDiskAccess(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> Bool {
        let protected = homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = try? FileHandle(forReadingFrom: protected) else {
            return false
        }
        try? handle.close()
        return true
    }
}
