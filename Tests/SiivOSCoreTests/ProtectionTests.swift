import XCTest
@testable import SiivOSCore

final class ProtectionTests: TemporaryDirectoryTestCase {
    // MARK: - Who signed a program

    func testCodeSignaturesAreRead() {
        let developer = """
        Executable=/Applications/Example.app/Contents/MacOS/Example
        Identifier=com.example.App
        Authority=Developer ID Application: Example Ltd (ABCDE12345)
        Authority=Developer ID Certification Authority
        Authority=Apple Root CA
        TeamIdentifier=ABCDE12345
        """
        XCTAssertEqual(CodeSignature.parse(developer), .developer(name: "Example Ltd"))

        let apple = "Identifier=com.apple.sh\nAuthority=Software Signing\nAuthority=Apple Code Signing Certification Authority\n"
        XCTAssertEqual(CodeSignature.parse(apple), .apple)

        XCTAssertEqual(CodeSignature.parse("Identifier=tool\nSignature=adhoc\nTeamIdentifier=not set\n"), .adHoc)
        XCTAssertEqual(CodeSignature.parse("/tmp/script.sh: code object is not signed at all\n"), .unsigned)
        XCTAssertEqual(CodeSignature.parse(""), .unknown)
    }

    // MARK: - Protection built into macOS

    func testBuiltInProtectionThatIsOnIsFine() {
        let section = SystemProtection.section(
            gatekeeper: "assessments enabled\n",
            integrityProtection: "System Integrity Protection status: enabled.\n",
            fileVault: "FileVault is On.\n",
            firewall: "Firewall is enabled. (State = 1)\n",
            xprotectVersion: "5300"
        )
        XCTAssertEqual(section.findings.count, 5)
        XCTAssertTrue(section.noteworthy.isEmpty)
        XCTAssertTrue(section.findings.contains { $0.explanation.contains("5300") })
    }

    func testBuiltInProtectionThatIsOffIsPointedOutCalmly() {
        let section = SystemProtection.section(
            gatekeeper: "assessments disabled\n",
            integrityProtection: "System Integrity Protection status: disabled.\n",
            fileVault: "FileVault is Off.\n",
            firewall: "Firewall is disabled. (State = 0)\n",
            xprotectVersion: nil
        )
        let levels = Dictionary(uniqueKeysWithValues: section.findings.map { ($0.id, $0.level) })
        XCTAssertEqual(levels["gatekeeper"], .attention)
        XCTAssertEqual(levels["system-integrity-protection"], .attention)
        XCTAssertEqual(levels["filevault"], .note)
        XCTAssertEqual(levels["firewall"], .note)
        // The most important findings come first.
        XCTAssertEqual(section.findings.first?.level, .attention)
        XCTAssertEqual(section.findings.last?.level, .note)
    }

    func testSettingsThatCouldNotBeReadAreLeftOut() {
        let section = SystemProtection.section(
            gatekeeper: nil, integrityProtection: nil, fileVault: nil, firewall: nil, xprotectVersion: nil
        )
        XCTAssertTrue(section.findings.isEmpty)
    }

    // MARK: - Background items

    private func item(
        label: String,
        program: String?,
        arguments: [String]? = nil,
        scope: BackgroundItem.Scope = .user,
        programExists: Bool = true
    ) -> BackgroundItem {
        BackgroundItem(
            url: home.appendingPathComponent("Library/LaunchAgents/\(label).plist"),
            label: label,
            program: program,
            arguments: arguments ?? (program.map { [$0] } ?? []),
            scope: scope,
            startsAutomatically: true,
            isDisabled: false,
            programExists: programExists
        )
    }

    /// A home folder that only exists as a path. Reviewing never touches the disk, and the
    /// tests' real folder sits inside a temporary folder, which the review rightly finds unusual.
    private let pretendHome = URL(fileURLWithPath: "/Users/tester")

    private func review(_ item: BackgroundItem, signature: CodeSignature = .developer(name: "Example Ltd")) -> ProtectionFinding {
        BackgroundItemReview.review(item, homeDirectory: pretendHome) { _ in signature }
    }

    func testAnOrdinarySignedUpdaterIsFine() {
        let finding = review(item(label: "com.example.updater", program: "/Applications/Example.app/Contents/MacOS/Updater"))
        XCTAssertEqual(finding.level, .fine)
        XCTAssertTrue(finding.explanation.contains("Example Ltd"))
        XCTAssertTrue(finding.canRemove)

        let system = review(item(label: "com.apple.thing", program: "/usr/libexec/thing"), signature: .apple)
        XCTAssertEqual(system.level, .fine)
    }

    func testKnownAdwareNamesGetAttentionButLookalikesDoNot() {
        XCTAssertEqual(review(item(label: "com.genieo.completer.update", program: "/Applications/Thing.app/Contents/MacOS/Thing")).level, .attention)
        XCTAssertEqual(review(item(label: "com.x.helper", program: "/Library/Advanced Mac Cleaner/helper")).level, .attention)

        XCTAssertNil(BackgroundItemReview.knownUnwantedName(in: "com.example.threadloader"))
        XCTAssertNil(BackgroundItemReview.knownUnwantedName(in: "org.spigotmc.server /usr/local/bin/conduit"))
        XCTAssertEqual(BackgroundItemReview.knownUnwantedName(in: "com.VSearch.agent"), "vsearch")
    }

    func testProgramsInUnusualPlacesGetAttention() {
        XCTAssertEqual(review(item(label: "a", program: "/tmp/updater")).level, .attention)
        XCTAssertEqual(review(item(label: "b", program: "/Users/Shared/helper")).level, .attention)
        XCTAssertEqual(review(item(label: "c", program: "/Users/tester/Downloads/tool")).level, .attention)
        XCTAssertEqual(review(item(label: "d", program: "/Users/tester/.hidden/agent")).level, .attention)
        // An app's own support folder is an ordinary place.
        XCTAssertEqual(review(item(label: "e", program: "/Users/tester/Library/Application Support/Example/helper")).level, .fine)
    }

    func testScriptsMissingProgramsAndUnsignedProgramsAreNotes() {
        XCTAssertEqual(review(item(label: "s", program: "/bin/sh", arguments: ["/bin/sh", "-c", "curl example.com | sh"]), signature: .apple).level, .note)
        XCTAssertEqual(review(item(label: "m", program: "/Applications/Gone.app/Contents/MacOS/Gone", programExists: false)).level, .note)
        XCTAssertEqual(review(item(label: "u", program: "/usr/local/bin/mytool"), signature: .unsigned).level, .note)
        XCTAssertEqual(review(item(label: "h", program: "/usr/local/bin/mytool"), signature: .adHoc).level, .note)
        XCTAssertEqual(review(item(label: "n", program: nil)).level, .fine)
    }

    func testOnlyTheUsersOwnBackgroundItemsCanBeRemoved() {
        XCTAssertTrue(review(item(label: "mine", program: "/Applications/A.app/Contents/MacOS/A", scope: .user)).canRemove)
        XCTAssertFalse(review(item(label: "all", program: "/Applications/A.app/Contents/MacOS/A", scope: .allUsers)).canRemove)
        XCTAssertFalse(review(item(label: "sys", program: "/Applications/A.app/Contents/MacOS/A", scope: .system)).canRemove)
    }

    // MARK: - Browser extensions

    private func writeJSON(_ object: Any, to relativePath: String) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }

    func testChromiumExtensionsAreFoundWithNamesAndAccess() throws {
        let chrome = "Library/Application Support/Google/Chrome"
        try writeJSON(
            ["name": "Ad Blocker", "version": "2.0", "permissions": ["storage", "<all_urls>"]],
            to: "\(chrome)/Default/Extensions/aaaa/1.0_0/manifest.json"
        )
        try writeJSON(
            ["name": "Ad Blocker", "version": "2.1", "host_permissions": ["*://*/*"]],
            to: "\(chrome)/Default/Extensions/aaaa/2.1_0/manifest.json"
        )
        try writeJSON(
            ["name": "__MSG_extName__", "version": "1.5", "default_locale": "en", "permissions": ["activeTab"]],
            to: "\(chrome)/Profile 1/Extensions/bbbb/1.5_0/manifest.json"
        )
        try writeJSON(
            ["extname": ["message": "Tab Tidier"]],
            to: "\(chrome)/Profile 1/Extensions/bbbb/1.5_0/_locales/en/messages.json"
        )
        try writeJSON(
            ["name": "Reader", "version": "3", "content_scripts": [["matches": ["https://example.com/*"]]]],
            to: "Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions/cccc/3_0/manifest.json"
        )
        // Not an extension folder.
        try makeFile("\(chrome)/Crashpad/settings.dat")

        let found = BrowserExtensions.findChromium(homeDirectory: home)
        let byName = Dictionary(uniqueKeysWithValues: found.map { ($0.name, $0) })

        XCTAssertEqual(found.count, 3)
        XCTAssertEqual(byName["Ad Blocker"]?.version, "2.1", "The newest installed version is the one that counts")
        XCTAssertEqual(byName["Ad Blocker"]?.hasBroadAccess, true)
        XCTAssertEqual(byName["Ad Blocker"]?.browser, "Chrome")
        XCTAssertEqual(byName["Tab Tidier"]?.profile, "Profile 1")
        XCTAssertEqual(byName["Tab Tidier"]?.hasBroadAccess, false)
        XCTAssertEqual(byName["Reader"]?.browser, "Brave")
        XCTAssertEqual(byName["Reader"]?.hasBroadAccess, false)
    }

    func testFirefoxListsOnlyExtensionsTheUserInstalled() throws {
        try writeJSON(
            ["addons": [
                ["id": "blocker@example.org", "type": "extension", "location": "app-profile", "version": "1.2", "active": true,
                 "defaultLocale": ["name": "Blocker"], "userPermissions": ["origins": ["<all_urls>"], "permissions": []]],
                ["id": "off@example.org", "type": "extension", "location": "app-profile", "version": "0.9", "active": false,
                 "defaultLocale": ["name": "Switched Off"], "userPermissions": ["origins": [], "permissions": []]],
                ["id": "builtin@mozilla.org", "type": "extension", "location": "app-builtin", "defaultLocale": ["name": "Built In"]],
                ["id": "theme@mozilla.org", "type": "theme", "location": "app-profile", "defaultLocale": ["name": "A Theme"]]
            ]],
            to: "Library/Application Support/Firefox/Profiles/abcd.default/extensions.json"
        )

        let found = BrowserExtensions.findFirefox(homeDirectory: home)

        XCTAssertEqual(found.map { $0.name }, ["Blocker", "Switched Off"])
        XCTAssertEqual(found[0].hasBroadAccess, true)
        XCTAssertEqual(found[0].isEnabled, true)
        XCTAssertEqual(found[1].isEnabled, false)
    }

    func testSafariExtensionsAreReadFromPluginKit() {
        let output = """
        +    com.example.Passwords.SafariExtension(7.9)
                    Path = /Applications/Passwords.app/Contents/PlugIns/SafariExtension.appex
                    UUID = 11111111-2222-3333-4444-555555555555
                    SDK = com.apple.Safari.extension
                    Parent Bundle = /Applications/Passwords.app
                    Display Name = Passwords
                    Parent Name = Passwords

        -    org.sample.Blocker.Extension(2.0.1)
                    Path = /Applications/Blocker.app/Contents/PlugIns/Extension.appex
                    Parent Name = Blocker
        """
        let found = BrowserExtensions.parseSafari(pluginKitOutput: output)

        XCTAssertEqual(found.map { $0.name }, ["Passwords", "Blocker"])
        XCTAssertEqual(found[0].version, "7.9")
        XCTAssertEqual(found[0].isEnabled, true)
        XCTAssertEqual(found[0].identifier, "com.example.Passwords.SafariExtension")
        XCTAssertEqual(found[1].isEnabled, false)
        XCTAssertEqual(found[1].version, "2.0.1")
        XCTAssertTrue(BrowserExtensions.parseSafari(pluginKitOutput: "").isEmpty)
    }

    func testExtensionsThatSeeEveryWebsiteAreNotes() {
        let wide = BrowserExtension(browser: "Chrome", profile: "Default", name: "Wide", version: "1", identifier: "w", url: nil, isEnabled: nil, hasBroadAccess: true)
        let narrow = BrowserExtension(browser: "Firefox", profile: "abcd.default", name: "Narrow", version: "1", identifier: "n", url: nil, isEnabled: false, hasBroadAccess: false)
        let section = BrowserExtensions.section(extensions: [narrow, wide])

        XCTAssertEqual(section.findings.map { $0.title }, ["Wide", "Narrow"])
        XCTAssertEqual(section.noteworthy.count, 1)
        XCTAssertEqual(section.findings[0].detail, "Chrome")
        XCTAssertTrue(section.findings[1].detail?.contains("switched off") ?? false)
    }

    // MARK: - Configuration profiles

    private func profilesJSON(_ profiles: [[String: Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "SPConfigurationProfileDataType": [
                ["_name": "spconfigprofile_user", "_items": profiles]
            ]
        ])
    }

    func testProfilesAreReadAndReviewed() throws {
        let data = try profilesJSON([
            [
                "_name": "Company Wi-Fi",
                "spconfigprofile_profile_identifier": "com.company.wifi",
                "spconfigprofile_organization": "Company Ltd",
                "spconfigprofile_verification_state": "verified",
                "_items": [["_name": "com.apple.wifi.managed"]]
            ],
            [
                "_name": "Company Security",
                "spconfigprofile_profile_identifier": "com.company.security",
                "spconfigprofile_organization": "Company Ltd",
                "spconfigprofile_verification_state": "verified",
                "_items": [["_name": "com.apple.dnsSettings.managed"], ["_name": "com.apple.security.root"]]
            ],
            [
                "_name": "Search Helper",
                "spconfigprofile_profile_identifier": "xyz.search.helper",
                "spconfigprofile_verification_state": "unsigned",
                "_items": [["_name": "com.google.Chrome"], ["_name": "com.apple.proxy.http.global"]]
            ]
        ])
        let profiles = ConfigurationProfiles.parse(systemProfilerJSON: data)
        XCTAssertEqual(profiles.map { $0.name }, ["Company Wi-Fi", "Company Security", "Search Helper"])
        XCTAssertEqual(profiles[1].payloadTypes, ["com.apple.dnsSettings.managed", "com.apple.security.root"])
        XCTAssertTrue(profiles[0].isVerified)
        XCTAssertFalse(profiles[2].isVerified)
        XCTAssertNil(profiles[2].organization)

        let section = ConfigurationProfiles.section(profiles: profiles)
        let levels = Dictionary(uniqueKeysWithValues: section.findings.map { ($0.title, $0.level) })
        XCTAssertEqual(levels["Company Wi-Fi"], .fine)
        XCTAssertEqual(levels["Company Security"], .note, "Traffic settings from a named organisation are normal on a managed Mac")
        XCTAssertEqual(levels["Search Helper"], .attention, "Traffic settings from nobody in particular are not")
        XCTAssertEqual(section.findings.first?.title, "Search Helper")
        XCTAssertTrue(section.findings.contains { $0.explanation.contains("Company Ltd") })
    }

    func testNoProfilesOrUnreadableDataGivesNoFindings() {
        XCTAssertTrue(ConfigurationProfiles.parse(systemProfilerJSON: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(ConfigurationProfiles.parse(systemProfilerJSON: Data("{\"SPConfigurationProfileDataType\": []}".utf8)).isEmpty)
        XCTAssertTrue(ConfigurationProfiles.section(profiles: []).findings.isEmpty)
    }

    // MARK: - App permissions

    func testPermissionsAreReadAndGroupedByKind() {
        let output = """
        kTCCServiceCamera|us.zoom.xos|2
        kTCCServiceCamera|com.example.denied|0
        kTCCServiceMicrophone|us.zoom.xos|2
        kTCCServiceSystemPolicyAllFiles|com.example.backup|2
        kTCCServiceSystemPolicyAllFiles|/usr/local/bin/tool|2
        kTCCServiceSomethingElse|com.example.other|2
        garbage line
        """
        let permissions = AppPermissions.parse(sqliteOutput: output)
        XCTAssertEqual(permissions.count, 6)
        XCTAssertEqual(permissions[1].isAllowed, false)

        let section = AppPermissions.section(
            permissions: permissions,
            appNames: ["us.zoom.xos": "Zoom", "com.example.backup": "Backup"]
        )
        XCTAssertNil(section.unavailableReason)
        XCTAssertEqual(section.findings.map { $0.id }, [
            "permission:kTCCServiceSystemPolicyAllFiles",
            "permission:kTCCServiceCamera",
            "permission:kTCCServiceMicrophone"
        ])
        XCTAssertEqual(section.findings[0].level, .note, "Full Disk Access is a wide power")
        XCTAssertTrue(section.findings[0].explanation.contains("Backup, tool"))
        XCTAssertEqual(section.findings[1].level, .fine)
        XCTAssertTrue(section.findings[1].explanation.contains("Zoom"))
        XCTAssertFalse(section.findings[1].explanation.contains("denied"))
    }

    func testPermissionsThatCannotBeReadSaySoInsteadOfLookingEmpty() {
        let section = AppPermissions.section(permissions: nil, appNames: [:])
        XCTAssertTrue(section.findings.isEmpty)
        XCTAssertNotNil(section.unavailableReason)
    }

    // MARK: - The report

    func testTheReportCountsByLevel() {
        let report = ProtectionReport(sections: [
            ProtectionSection(id: "a", title: "A", summary: "", findings: [
                ProtectionFinding(id: "1", level: .fine, title: "x", explanation: ""),
                ProtectionFinding(id: "2", level: .note, title: "y", explanation: "")
            ]),
            ProtectionSection(id: "b", title: "B", summary: "", findings: [
                ProtectionFinding(id: "3", level: .attention, title: "z", explanation: "")
            ])
        ])
        XCTAssertEqual(report.count(of: .fine), 1)
        XCTAssertEqual(report.count(of: .note), 1)
        XCTAssertEqual(report.count(of: .attention), 1)
        XCTAssertEqual(report.overallLevel, .attention)
        XCTAssertEqual(ProtectionReport(sections: []).overallLevel, .fine)
    }

    #if os(macOS)
    func testTheCheckRunsOnThisMac() {
        var steps: [String] = []
        let report = ProtectionCheck.run { steps.append($0) }
        XCTAssertEqual(report.sections.map { $0.id }, ["macos", "background-items", "browser-extensions", "profiles", "permissions"])
        XCTAssertEqual(steps.count, 5)
        XCTAssertFalse(report.sections[0].findings.isEmpty, "macOS's own protection settings should be readable")
    }
    #endif
}
