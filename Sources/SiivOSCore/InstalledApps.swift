import Foundation

/// An app found in one of the Applications folders.
public struct InstalledApp: Equatable, Sendable {
    public let url: URL
    /// The app's name as shown in Finder, without ".app".
    public let name: String
    /// The app's unique identifier, for example "com.example.Notes", if it declares one.
    public let bundleIdentifier: String?
    /// The version shown to users, for example "2.1", if the app declares one.
    public let version: String?
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
        let info = infoDictionary(ofAppAt: url)
        return InstalledApp(
            url: url,
            name: url.deletingPathExtension().lastPathComponent,
            bundleIdentifier: nonEmptyString(info["CFBundleIdentifier"]),
            version: nonEmptyString(info["CFBundleShortVersionString"])
        )
    }

    /// Reads the app's Info.plist. Mac apps keep it in "Contents"; iPhone and iPad apps
    /// running on a Mac keep it in "WrappedBundle". An app without one gives an empty result.
    private static func infoDictionary(ofAppAt url: URL) -> [String: Any] {
        for location in ["Contents/Info.plist", "WrappedBundle/Info.plist"] {
            let file = url.appendingPathComponent(location)
            guard let data = try? Data(contentsOf: file),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                  let dictionary = plist as? [String: Any]
            else {
                continue
            }
            return dictionary
        }
        return [:]
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else {
            return nil
        }
        return text
    }
}
