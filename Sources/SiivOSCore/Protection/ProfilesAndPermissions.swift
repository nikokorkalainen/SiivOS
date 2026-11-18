import Foundation

// MARK: - Configuration profiles

/// A configuration profile installed on the Mac: a bundle of settings put there by an
/// organisation, an app, or sometimes by adware.
struct ConfigurationProfile: Equatable {
    let name: String
    let identifier: String
    /// Who it says it comes from, if it says.
    let organization: String?
    /// True when macOS could verify who signed it.
    let isVerified: Bool
    /// The kinds of settings it contains, for example "com.apple.dnsSettings.managed".
    let payloadTypes: [String]
}

/// Reads and reviews configuration profiles. Read-only.
enum ConfigurationProfiles {
    /// Kinds of settings that affect where the Mac's traffic goes or what the browser
    /// does, with what each means in plain words.
    private static var sensitivePayloads: [(marker: String, meaning: String)] {
        [
            ("dnssettings", tr("changes which servers look up website addresses")),
            ("dnsproxy", tr("changes which servers look up website addresses")),
            ("proxy", tr("sends web traffic through another server")),
            ("webcontent-filter", tr("filters web traffic")),
            ("vpn", tr("sets up a VPN")),
            ("security.root", tr("adds a certificate that can let its owner read secure traffic")),
            ("security.pem", tr("adds a certificate that can let its owner read secure traffic")),
            ("com.google.chrome", tr("controls browser settings")),
            ("com.apple.safari", tr("controls browser settings")),
            ("org.mozilla.firefox", tr("controls browser settings")),
            ("com.microsoft.edgemac", tr("controls browser settings"))
        ]
    }

    /// Reads the output of `system_profiler SPConfigurationProfileDataType -json`.
    ///
    /// Profiles are found wherever they sit in the data: any entry that carries a profile
    /// identifier is a profile, and the entries inside it are its payloads.
    static func parse(systemProfilerJSON data: Data) -> [ConfigurationProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        var profiles: [ConfigurationProfile] = []
        collect(from: root, into: &profiles)
        return profiles
    }

    private static func collect(from value: Any, into profiles: inout [ConfigurationProfile]) {
        if let list = value as? [Any] {
            for element in list {
                collect(from: element, into: &profiles)
            }
            return
        }
        guard let entry = value as? [String: Any] else {
            return
        }
        if let identifier = entry["spconfigprofile_profile_identifier"] as? String {
            let payloads = entry["_items"] as? [[String: Any]] ?? []
            let state = (entry["spconfigprofile_verification_state"] as? String ?? "").lowercased()
            let organization = entry["spconfigprofile_organization"] as? String
            profiles.append(
                ConfigurationProfile(
                    name: entry["_name"] as? String ?? identifier,
                    identifier: identifier,
                    organization: organization.flatMap { $0.isEmpty ? nil : $0 },
                    isVerified: state.contains("verified") && !state.contains("unverified") && !state.contains("not"),
                    payloadTypes: payloads.compactMap { $0["_name"] as? String }
                )
            )
            return
        }
        for nested in entry.values {
            collect(from: nested, into: &profiles)
        }
    }

    static func section(profiles: [ConfigurationProfile]) -> ProtectionSection {
        let findings = profiles.map { profile -> ProtectionFinding in
            let meanings = sensitiveMeanings(of: profile)
            let source = profile.organization.map { tr("Installed by %1$@.", $0) }
                ?? tr("It does not say who installed it.")

            let level: ProtectionFinding.Level
            let explanation: String
            if meanings.isEmpty {
                level = .fine
                explanation = source + " " + tr("It does not change where this Mac's traffic goes.")
            } else {
                // Settings like these are normal on a Mac managed by an employer or school,
                // and unusual on a personal Mac.
                level = (profile.organization == nil && !profile.isVerified) ? .attention : .note
                explanation = source + " " + tr("It %1$@. That is normal on a Mac managed by an employer or school. On a personal Mac, check that you know where it came from.", meanings.joined(separator: ", "))
            }
            return ProtectionFinding(
                id: "profile:" + profile.identifier,
                level: level,
                title: profile.name,
                explanation: explanation,
                detail: profile.identifier
            )
        }
        return ProtectionSection(
            id: "profiles",
            title: tr("Configuration profiles"),
            summary: tr("Bundles of settings installed on this Mac, usually by an employer or school. A profile can redirect web traffic or change browser settings, which adware sometimes abuses. Profiles are removed in System Settings, under Privacy & Security, Profiles."),
            findings: findings
        )
    }

    /// What the profile's sensitive settings do, in plain words, without repeats.
    private static func sensitiveMeanings(of profile: ConfigurationProfile) -> [String] {
        var meanings: [String] = []
        for payload in profile.payloadTypes {
            let lowered = payload.lowercased()
            for sensitive in sensitivePayloads where lowered.contains(sensitive.marker) {
                if !meanings.contains(sensitive.meaning) {
                    meanings.append(sensitive.meaning)
                }
            }
        }
        return meanings
    }
}

// MARK: - App permissions

/// One permission an app has been given, or refused, in macOS's privacy settings.
struct AppPermission: Equatable {
    /// macOS's own name for the permission, for example "kTCCServiceCamera".
    let service: String
    /// The app's identifier, or the path of a program without one.
    let client: String
    let isAllowed: Bool
}

/// Reads which apps hold which privacy permissions. Read-only.
enum AppPermissions {
    /// The permissions worth showing, in the order they are listed, with their names and
    /// whether holding one gives an app unusually wide powers.
    private static var services: [(service: String, name: String, isPowerful: Bool)] {
        [
            ("kTCCServiceSystemPolicyAllFiles", tr("Full Disk Access"), true),
            ("kTCCServiceAccessibility", tr("Accessibility (controlling the Mac)"), true),
            ("kTCCServiceScreenCapture", tr("Screen recording"), true),
            ("kTCCServiceListenEvent", tr("Input monitoring (seeing what you type)"), true),
            ("kTCCServiceCamera", tr("Camera"), false),
            ("kTCCServiceMicrophone", tr("Microphone"), false),
            ("kTCCServiceAddressBook", tr("Contacts"), false),
            ("kTCCServiceCalendar", tr("Calendars"), false),
            ("kTCCServicePhotos", tr("Photos"), false)
        ]
    }

    /// Reads the rows printed by
    /// `sqlite3 -readonly <database> "SELECT service, client, auth_value FROM access"`,
    /// which look like "kTCCServiceCamera|us.zoom.xos|2". A value of 2 or more means allowed.
    static func parse(sqliteOutput output: String) -> [AppPermission] {
        output.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false)
            guard fields.count >= 3, let value = Int(fields[fields.count - 1]) else {
                return nil
            }
            return AppPermission(
                service: String(fields[0]),
                // A client could in principle contain the separator, so take everything in between.
                client: fields[1..<(fields.count - 1)].joined(separator: "|"),
                isAllowed: value >= 2
            )
        }
    }

    /// - Parameters:
    ///   - permissions: What was read, or `nil` when macOS did not let SiivOS read it.
    ///   - appNames: Names of installed apps by identifier, to show names instead of identifiers.
    static func section(permissions: [AppPermission]?, appNames: [String: String]) -> ProtectionSection {
        let title = tr("App permissions")
        let summary = tr("Which apps you have allowed to use sensitive parts of this Mac. The first four give an app wide powers, so those lists are worth keeping short. Permissions are changed in System Settings, under Privacy & Security.")
        guard let permissions else {
            return ProtectionSection(
                id: "permissions",
                title: title,
                summary: summary,
                findings: [],
                unavailableReason: tr("macOS only shows this list to apps with Full Disk Access. To see it here, give SiivOS Full Disk Access in System Settings, under Privacy & Security, then check again.")
            )
        }

        var findings: [ProtectionFinding] = []
        for service in services {
            var seen = Set<String>()
            let apps = permissions
                .filter { $0.service == service.service && $0.isAllowed }
                .map { displayName(for: $0.client, appNames: appNames) }
                .filter { seen.insert($0).inserted }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            guard !apps.isEmpty else {
                continue
            }
            findings.append(
                ProtectionFinding(
                    id: "permission:" + service.service,
                    level: service.isPowerful ? .note : .fine,
                    title: service.name,
                    explanation: tr("Allowed: %1$@.", apps.joined(separator: ", "))
                )
            )
        }
        return ProtectionSection(id: "permissions", title: title, summary: summary, findings: findings)
    }

    /// The app's name when it is installed, otherwise the file name of a path, otherwise
    /// the identifier as it is.
    private static func displayName(for client: String, appNames: [String: String]) -> String {
        if let name = appNames[client.lowercased()] {
            return name
        }
        if client.hasPrefix("/") {
            return URL(fileURLWithPath: client).deletingPathExtension().lastPathComponent
        }
        return client
    }
}
