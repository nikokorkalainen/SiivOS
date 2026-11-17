import Foundation

/// An app found in one of the Applications folders.
public struct InstalledApp: Equatable, Sendable {
    public let url: URL
    /// The app's name as shown in Finder, without ".app".
    public let name: String
    /// The app's unique identifier, for example "com.example.Notes", if it declares one.
    public let bundleIdentifier: String?
}

/// Finds the apps installed on this Mac. Read-only.
public enum InstalledApps {
    /// The folders where apps normally live.
    public static func standardDirectories(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())
    ) -> [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            homeDirectory.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    /// Every app in the given folders, including apps one folder down
    /// (for example "/Applications/Utilities/Terminal.app").
    public static func find(in directories: [URL], fileManager: FileManager = .default) -> [InstalledApp] {
        var apps: [InstalledApp] = []
        for directory in directories {
            for item in contents(of: directory, fileManager: fileManager) {
                if item.pathExtension.lowercased() == "app" {
                    apps.append(app(at: item))
                } else {
                    let nested = contents(of: item, fileManager: fileManager)
                    apps.append(contentsOf: nested.filter { $0.pathExtension.lowercased() == "app" }.map(app(at:)))
                }
            }
        }
        return apps
    }

    private static func contents(of directory: URL, fileManager: FileManager) -> [URL] {
        let found = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return found ?? []
    }

    private static func app(at url: URL) -> InstalledApp {
        InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleIdentifier(ofAppAt: url)
        )
    }

    /// Reads the identifier from the app's Info.plist. Mac apps keep it in "Contents";
    /// iPhone and iPad apps running on a Mac keep it in "WrappedBundle".
    private static func bundleIdentifier(ofAppAt url: URL) -> String? {
        for location in ["Contents/Info.plist", "WrappedBundle/Info.plist"] {
            let file = url.appendingPathComponent(location)
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dictionary = plist as? [String: Any],
                  let identifier = dictionary["CFBundleIdentifier"] as? String,
                  !identifier.isEmpty
            else {
                continue
            }
            return identifier
        }
        return nil
    }
}
