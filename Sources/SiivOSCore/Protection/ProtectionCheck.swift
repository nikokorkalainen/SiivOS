import Foundation

/// Runs every protection check and gathers the results. Only reads; never changes anything.
public enum ProtectionCheck {
    /// - Parameter progress: Called with the name of each check just before it starts.
    public static func run(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        progress: ((String) -> Void)? = nil
    ) -> ProtectionReport {
        var sections: [ProtectionSection] = []

        progress?(tr("Protection built into macOS"))
        sections.append(SystemProtection.check())

        progress?(tr("Background items"))
        let items = BackgroundItems.find(in: BackgroundItems.standardDirectories(homeDirectory: homeDirectory))
        sections.append(
            BackgroundItemReview.section(items: items, homeDirectory: homeDirectory) { path in
                CodeSignature.read(path: path)
            }
        )

        progress?(tr("Browser extensions"))
        var extensions = BrowserExtensions.findChromium(homeDirectory: homeDirectory)
        extensions += BrowserExtensions.findFirefox(homeDirectory: homeDirectory)
        for kind in ["com.apple.Safari.web-extension", "com.apple.Safari.extension"] {
            if let output = SystemCommand.output(of: "/usr/bin/pluginkit", ["-mAvvv", "-p", kind]) {
                extensions += BrowserExtensions.parseSafari(pluginKitOutput: output)
            }
        }
        sections.append(BrowserExtensions.section(extensions: extensions))

        progress?(tr("Configuration profiles"))
        let profilesOutput = SystemCommand.output(
            of: "/usr/sbin/system_profiler",
            ["SPConfigurationProfileDataType", "-json"]
        )
        let profiles = profilesOutput.map { ConfigurationProfiles.parse(systemProfilerJSON: Data($0.utf8)) } ?? []
        sections.append(ConfigurationProfiles.section(profiles: profiles))

        progress?(tr("App permissions"))
        sections.append(
            AppPermissions.section(
                permissions: readPermissions(homeDirectory: homeDirectory),
                appNames: installedAppNames(homeDirectory: homeDirectory)
            )
        )

        return ProtectionReport(sections: sections)
    }

    /// Reads macOS's two lists of privacy permissions: the user's and the Mac-wide one.
    /// Returns `nil` when neither can be read, which is the case without Full Disk Access.
    private static func readPermissions(homeDirectory: URL) -> [AppPermission]? {
        let databases = [
            homeDirectory.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db").path,
            "/Library/Application Support/com.apple.TCC/TCC.db"
        ]
        var all: [AppPermission] = []
        var couldRead = false
        for database in databases where FileManager.default.isReadableFile(atPath: database) {
            guard let output = SystemCommand.output(
                of: "/usr/bin/sqlite3",
                ["-readonly", database, "SELECT service, client, auth_value FROM access"]
            ) else {
                continue
            }
            let permissions = AppPermissions.parse(sqliteOutput: output)
            // An unreadable database prints nothing; a readable one always has some rows.
            if !permissions.isEmpty {
                couldRead = true
                all += permissions
            }
        }
        return couldRead ? all : nil
    }

    private static func installedAppNames(homeDirectory: URL) -> [String: String] {
        var names: [String: String] = [:]
        let apps = InstalledApps.find(in: InstalledApps.standardDirectories(homeDirectory: homeDirectory))
        for app in apps {
            if let identifier = app.bundleIdentifier {
                names[identifier.lowercased()] = app.name
            }
        }
        return names
    }
}
