import Foundation

/// An extension installed in a web browser.
public struct BrowserExtension: Equatable, Identifiable, Sendable {
    /// The browser's name, for example "Chrome".
    public let browser: String
    /// The browser profile it is installed in, when the browser has several.
    public let profile: String?
    public let name: String
    public let version: String?
    /// The extension's own identifier.
    public let identifier: String
    /// Where the extension lives on disk, if known.
    public let url: URL?
    /// Whether it is switched on. `nil` when the browser does not say.
    public let isEnabled: Bool?
    /// True when the extension may read and change every website.
    public let hasBroadAccess: Bool

    public var id: String {
        [browser, profile ?? "", identifier].joined(separator: "|")
    }
}

/// Finds the extensions installed in the common browsers. Read-only.
///
/// SiivOS lists extensions and says which can see every website. It does not remove
/// them: a browser keeps its own records of its extensions, so removing one is done in
/// the browser itself.
enum BrowserExtensions {
    /// Browsers built on Chromium, with where each keeps its data under
    /// `~/Library/Application Support`.
    private static let chromiumBrowsers: [(name: String, folder: String)] = [
        ("Chrome", "Google/Chrome"),
        ("Edge", "Microsoft Edge"),
        ("Brave", "BraveSoftware/Brave-Browser"),
        ("Arc", "Arc/User Data"),
        ("Vivaldi", "Vivaldi"),
        ("Opera", "com.operasoftware.Opera"),
        ("Chromium", "Chromium")
    ]

    /// Patterns that give an extension access to every website.
    private static let broadPatterns: Set<String> = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]

    // MARK: - Chromium browsers

    static func findChromium(homeDirectory: URL, fileManager: FileManager = .default) -> [BrowserExtension] {
        let support = homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
        var found: [BrowserExtension] = []
        for browser in chromiumBrowsers {
            let dataFolder = support.appendingPathComponent(browser.folder, isDirectory: true)
            for profile in folders(in: dataFolder, fileManager: fileManager) {
                let extensionsFolder = profile.appendingPathComponent("Extensions", isDirectory: true)
                for extensionFolder in folders(in: extensionsFolder, fileManager: fileManager) {
                    // Each extension has one folder per installed version; the last is the newest.
                    let versions = folders(in: extensionFolder, fileManager: fileManager)
                        .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
                    guard let newest = versions.last,
                          let manifest = json(at: newest.appendingPathComponent("manifest.json"))
                    else {
                        continue
                    }
                    found.append(
                        BrowserExtension(
                            browser: browser.name,
                            profile: profile.lastPathComponent,
                            name: chromiumName(manifest: manifest, folder: newest) ?? extensionFolder.lastPathComponent,
                            version: manifest["version"] as? String,
                            identifier: extensionFolder.lastPathComponent,
                            url: extensionFolder,
                            isEnabled: nil,
                            hasBroadAccess: chromiumHasBroadAccess(manifest)
                        )
                    )
                }
            }
        }
        return found
    }

    /// An extension's name. Many store it as "__MSG_appName__", which points into a
    /// separate file of translated texts.
    private static func chromiumName(manifest: [String: Any], folder: URL) -> String? {
        guard let name = manifest["name"] as? String, !name.isEmpty else {
            return nil
        }
        guard name.hasPrefix("__MSG_"), name.hasSuffix("__") else {
            return name
        }
        let key = String(name.dropFirst(6).dropLast(2)).lowercased()
        let locales = [manifest["default_locale"] as? String, "en", "en_US"].compactMap { $0 }
        for locale in locales {
            let file = folder.appendingPathComponent("_locales/\(locale)/messages.json")
            guard let messages = json(at: file) else {
                continue
            }
            for (messageKey, value) in messages where messageKey.lowercased() == key {
                if let message = (value as? [String: Any])?["message"] as? String, !message.isEmpty {
                    return message
                }
            }
        }
        return nil
    }

    private static func chromiumHasBroadAccess(_ manifest: [String: Any]) -> Bool {
        var patterns: [String] = []
        patterns += manifest["permissions"] as? [String] ?? []
        patterns += manifest["host_permissions"] as? [String] ?? []
        for script in manifest["content_scripts"] as? [[String: Any]] ?? [] {
            patterns += script["matches"] as? [String] ?? []
        }
        return patterns.contains { broadPatterns.contains($0) }
    }

    // MARK: - Firefox

    static func findFirefox(homeDirectory: URL, fileManager: FileManager = .default) -> [BrowserExtension] {
        let profiles = homeDirectory.appendingPathComponent("Library/Application Support/Firefox/Profiles", isDirectory: true)
        var found: [BrowserExtension] = []
        for profile in folders(in: profiles, fileManager: fileManager) {
            guard let registry = json(at: profile.appendingPathComponent("extensions.json")),
                  let addons = registry["addons"] as? [[String: Any]]
            else {
                continue
            }
            for addon in addons {
                // Only extensions the user installed, not the parts Firefox ships with.
                guard addon["type"] as? String == "extension",
                      addon["location"] as? String == "app-profile",
                      let identifier = addon["id"] as? String
                else {
                    continue
                }
                let name = (addon["defaultLocale"] as? [String: Any])?["name"] as? String
                let permissions = addon["userPermissions"] as? [String: Any]
                let origins = permissions?["origins"] as? [String] ?? []
                found.append(
                    BrowserExtension(
                        browser: "Firefox",
                        profile: profile.lastPathComponent,
                        name: name ?? identifier,
                        version: addon["version"] as? String,
                        identifier: identifier,
                        url: (addon["path"] as? String).map { URL(fileURLWithPath: $0) },
                        isEnabled: addon["active"] as? Bool,
                        hasBroadAccess: origins.contains { broadPatterns.contains($0) }
                    )
                )
            }
        }
        return found
    }

    // MARK: - Safari

    /// Reads what `pluginkit -mAvvv -p <kind>` prints about Safari's extensions. Each one
    /// starts with a line like "+    com.example.Extension(1.2)", where "+" means switched
    /// on and "-" switched off, followed by indented "Key = value" lines.
    static func parseSafari(pluginKitOutput output: String) -> [BrowserExtension] {
        var found: [BrowserExtension] = []
        var identifier: String?
        var version: String?
        var isEnabled: Bool?
        var fields: [String: String] = [:]

        func finish() {
            guard let identifier else { return }
            found.append(
                BrowserExtension(
                    browser: "Safari",
                    profile: nil,
                    name: fields["Display Name"] ?? fields["Parent Name"] ?? identifier,
                    version: version,
                    identifier: identifier,
                    url: fields["Path"].map { URL(fileURLWithPath: $0) },
                    isEnabled: isEnabled,
                    // Safari asks for website access one site at a time, so there is no
                    // blanket permission to read here.
                    hasBroadAccess: false
                )
            )
        }

        for rawLine in output.split(whereSeparator: { $0.isNewline }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if let equals = line.range(of: " = ") {
                fields[String(line[..<equals.lowerBound])] = String(line[equals.upperBound...])
                continue
            }
            guard line.hasSuffix(")"), let open = line.lastIndex(of: "(") else {
                continue
            }
            // A new extension starts here; store the one before it.
            finish()
            fields = [:]
            var head = String(line[..<open])
            isEnabled = nil
            if let mark = head.first, "+-!".contains(mark) {
                isEnabled = mark == "+"
                head = String(head.dropFirst())
            }
            identifier = head.trimmingCharacters(in: .whitespaces)
            version = String(line[line.index(after: open)...].dropLast())
        }
        finish()
        return found
    }

    // MARK: - Turning extensions into findings

    static func section(extensions: [BrowserExtension]) -> ProtectionSection {
        let findings = extensions.map { item -> ProtectionFinding in
            var place = item.browser
            if let profile = item.profile, profile != "Default" {
                place += ", " + profile
            }
            if item.isEnabled == false {
                place += ", " + tr("switched off")
            }
            return ProtectionFinding(
                id: item.id,
                level: item.hasBroadAccess ? .note : .fine,
                title: item.name,
                explanation: item.hasBroadAccess
                    ? tr("It can read and change every website you visit. Ad blockers and password managers need that, but check that you installed it yourself.")
                    : tr("It only works on the websites it was made for, or when you ask it to."),
                detail: place,
                fileURL: item.url
            )
        }
        return ProtectionSection(
            id: "browser-extensions",
            title: tr("Browser extensions"),
            summary: tr("Add-ons installed in your web browsers. An extension that can see every website sees everything you do there, so it is worth knowing which ones you have. To remove one, use the browser's own extensions page."),
            findings: findings
        )
    }

    // MARK: - Helpers

    private static func folders(in directory: URL, fileManager: FileManager) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func json(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else {
            return nil
        }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
