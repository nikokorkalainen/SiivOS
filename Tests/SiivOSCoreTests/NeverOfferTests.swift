import XCTest
@testable import SiivOSCore

final class NeverOfferTests: TemporaryDirectoryTestCase {
    private func names(_ findings: [Finding]) -> [String] {
        findings.map { $0.url.lastPathComponent }.sorted()
    }

    // MARK: - The never-offer list

    func testOrdinaryAppDataMayBeOffered() {
        XCTAssertNil(NeverOffer.category(forItemNamed: "com.example.Browser"))
        XCTAssertNil(NeverOffer.category(forItemNamed: "Spotify"))
        XCTAssertNil(NeverOffer.category(forItemNamed: "org.mozilla.firefox"))
        // "eset" is part of this name, but it is not the security vendor.
        XCTAssertNil(NeverOffer.category(forItemNamed: "com.example.presets"))
    }

    func testProtectedKindsOfDataAreRecognised() {
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.apple.Safari"), .macOS)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "COM.APPLE.Music"), .macOS)

        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.1password.1password"), .signIn)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.bitwarden.desktop"), .signIn)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "Authy Desktop"), .signIn)

        XCTAssertEqual(NeverOffer.category(forItemNamed: "CloudKit"), .sync)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.getdropbox.dropbox"), .sync)

        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.crowdstrike.falcon.Agent"), .security)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.jamf.management.Jamf"), .security)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.eset.endpoint"), .security)
        XCTAssertEqual(NeverOffer.category(forItemNamed: "com.microsoft.CompanyPortalMac"), .security)
    }

    func testEveryCategoryExplainsItself() {
        for category in NeverOffer.Category.allCases {
            XCTAssertFalse(category.title.isEmpty)
            XCTAssertFalse(category.explanation.isEmpty)
        }
    }

    // MARK: - Scanners leave protected data out

    func testCachesAndLogsOfProtectedSoftwareAreNeverListed() throws {
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)
        try makeFile("Library/Caches/com.1password.1password/data.bin", bytes: 500_000)
        try makeFile("Library/Caches/com.crowdstrike.falcon/data.bin", bytes: 500_000)
        try makeFile("Library/Caches/CloudKit/data.bin", bytes: 500_000)
        try makeFile("Library/Logs/Example/app.log", bytes: 500_000)
        try makeFile("Library/Logs/JAMF/jamf.log", bytes: 500_000)

        XCTAssertEqual(
            names(try CachesScanner(homeDirectory: home, minimumBytes: 200_000).scan()),
            ["com.example.Browser"]
        )
        XCTAssertEqual(
            names(try LogsScanner(homeDirectory: home, minimumBytes: 200_000).scan()),
            ["Example"]
        )
    }

    func testLeftoversOfProtectedSoftwareAreNeverListed() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Application Support/com.gone.Tool/data.bin", bytes: 500_000)
        try makeFile("Library/Application Support/com.bitwarden.desktop/data.bin", bytes: 500_000)

        let scanner = LeftoversScanner(
            homeDirectory: home,
            applicationDirectories: [applications],
            minimumBytes: 200_000
        )
        XCTAssertEqual(names(try scanner.scan()), ["com.gone.Tool"])
    }

    // MARK: - Open apps

    func testItemsAreMatchedToOpenApps() {
        let apps = [
            RunningApp(name: "Google Chrome", bundleIdentifier: "com.google.Chrome"),
            RunningApp(name: "Notes", bundleIdentifier: nil)
        ]
        func owner(_ name: String) -> String? {
            RunningApp.using(itemNamed: name, among: apps)?.name
        }

        XCTAssertEqual(owner("com.google.Chrome"), "Google Chrome")
        XCTAssertEqual(owner("COM.GOOGLE.CHROME.helper"), "Google Chrome")
        XCTAssertEqual(owner("com.google"), "Google Chrome")
        XCTAssertEqual(owner("Google"), "Google Chrome")
        XCTAssertEqual(owner("Google Chrome"), "Google Chrome")
        XCTAssertEqual(owner("notes"), "Notes")

        XCTAssertNil(owner("com.google.ChromeBeta"))
        XCTAssertNil(owner("com.example.Browser"))
        XCTAssertNil(owner("com"))
        XCTAssertNil(owner("Chrome Helper Tool"))
    }

    func testCachesAndLogsOfOpenAppsAreListedButHeldBack() throws {
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)
        try makeFile("Library/Caches/com.example.Editor/data.bin", bytes: 500_000)
        try makeFile("Library/Logs/Browser/app.log", bytes: 500_000)
        let open = [RunningApp(name: "Browser", bundleIdentifier: "com.example.Browser")]

        let caches = try CachesScanner(homeDirectory: home, minimumBytes: 200_000, runningApps: open).scan()
        let heldBack = caches.filter { $0.heldBackReason != nil }
        XCTAssertEqual(names(caches), ["com.example.Browser", "com.example.Editor"])
        XCTAssertEqual(names(heldBack), ["com.example.Browser"])
        XCTAssertTrue(heldBack[0].heldBackReason?.contains("Browser is open") ?? false)

        let logs = try LogsScanner(homeDirectory: home, minimumBytes: 200_000, runningApps: open).scan()
        XCTAssertNotNil(logs.first?.heldBackReason)
    }

    func testAnOpenAppCountsAsInstalledWhereverItIsKept() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Application Support/com.portable.Tool/data.bin", bytes: 500_000)
        let open = [RunningApp(name: "Tool", bundleIdentifier: "com.portable.Tool")]

        let withoutOpenApps = LeftoversScanner(
            homeDirectory: home, applicationDirectories: [applications], minimumBytes: 200_000
        )
        let withOpenApps = LeftoversScanner(
            homeDirectory: home, applicationDirectories: [applications], minimumBytes: 200_000, runningApps: open
        )

        XCTAssertEqual(names(try withoutOpenApps.scan()), ["com.portable.Tool"])
        XCTAssertEqual(try withOpenApps.scan(), [])
    }

    // MARK: - Data nothing may remove

    func testPasswordsMailAndMessagesCanNeverBeRemoved() throws {
        let rules = SafetyRules(
            homeDirectory: home,
            holdingDirectory: baseDirectory.appendingPathComponent("HoldingArea", isDirectory: true)
        )
        let keychain = try makeFile("Library/Keychains/login.keychain-db")
        let mailbox = try makeFile("Library/Mail/V10/Mailbox/message.emlx")
        let chat = try makeFile("Library/Messages/chat.db")
        let ordinary = try makeFile("Library/Application Support/Mailer/data.db")

        XCTAssertNotNil(rules.reasonToRefuse(keychain))
        XCTAssertNotNil(rules.reasonToRefuse(mailbox))
        XCTAssertNotNil(rules.reasonToRefuse(chat))
        XCTAssertNil(rules.reasonToRefuse(ordinary))

        let core = try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
        let plan = core.plan(removing: [keychain, ordinary], reason: "Test.")
        XCTAssertEqual(plan.items.map { $0.url.lastPathComponent }, ["data.db"])
        XCTAssertEqual(plan.refused.count, 1)
    }
}
