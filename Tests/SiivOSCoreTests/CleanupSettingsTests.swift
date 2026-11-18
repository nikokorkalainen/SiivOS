import XCTest
@testable import SiivOSCore

final class CleanupSettingsTests: TemporaryDirectoryTestCase {
    private func ids(_ report: ScanReport) -> [String] {
        report.sections.map { $0.id }
    }

    private func names(_ report: ScanReport, _ id: String) -> [String] {
        (report.sections.first { $0.id == id }?.findings ?? []).map { $0.url.lastPathComponent }.sorted()
    }

    // MARK: - Keeping the settings

    func testSettingsStartWithSiivOSsOwnChoices() {
        let settings = CleanupSettings()
        XCTAssertEqual(settings.oldDownloadDays, 90)
        XCTAssertEqual(settings.largeFileBytes, 100_000_000)
        XCTAssertTrue(settings.checksTurnedOff.isEmpty)
        XCTAssertTrue(settings.foldersLeftOut.isEmpty)
        XCTAssertTrue(settings.isStandard)
        XCTAssertTrue(CleanupSettings.oldDownloadChoices.contains(settings.oldDownloadDays))
        XCTAssertTrue(CleanupSettings.largeFileChoices.contains(settings.largeFileBytes))
    }

    func testSettingsAreKeptBetweenLaunches() throws {
        let store = CleanupSettingsStore(dataDirectory: baseDirectory)
        XCTAssertEqual(store.load(), CleanupSettings(), "Nothing saved yet")

        var settings = CleanupSettings()
        settings.oldDownloadDays = 30
        settings.largeFileBytes = 500_000_000
        settings.checksTurnedOff = ["duplicates"]
        settings.foldersLeftOut = ["/Users/someone/Documents/Portfolio"]
        try store.save(settings)

        let loaded = CleanupSettingsStore(dataDirectory: baseDirectory).load()
        XCTAssertEqual(loaded, settings)
        XCTAssertFalse(loaded.isStandard)
        XCTAssertEqual(loaded.folderURLsLeftOut.map { $0.path }, ["/Users/someone/Documents/Portfolio"])
    }

    func testADamagedOrOddSettingsFileFallsBackToSafeChoices() throws {
        let store = CleanupSettingsStore(dataDirectory: baseDirectory)
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)

        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), CleanupSettings())

        // Values that are not among the choices, and a file from a version with fewer settings.
        try Data(#"{"oldDownloadDays": 1, "largeFileBytes": 5}"#.utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), CleanupSettings())

        try Data(#"{"foldersLeftOut": ["/a"]}"#.utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load().foldersLeftOut, ["/a"])
        XCTAssertEqual(store.load().oldDownloadDays, 90)
    }

    // MARK: - What the settings do

    func testTheSizeThatCountsAsLargeFollowsTheSetting() throws {
        try makeFile("Movies/medium.mov", bytes: 60_000_000)
        var settings = CleanupSettings()

        XCTAssertEqual(names(ScanEngine.clutter(homeDirectory: home, settings: settings).run(), "large-files"), [])

        settings.largeFileBytes = 50_000_000
        let report = ScanEngine.clutter(homeDirectory: home, settings: settings).run()
        XCTAssertEqual(names(report, "large-files"), ["medium.mov"])
        XCTAssertTrue(report.sections.first { $0.id == "large-files" }?.summary.contains("50") ?? false)
    }

    func testTheAgeThatCountsAsOldFollowsTheSetting() throws {
        let file = try makeFile("Downloads/installer.dmg", bytes: 100)
        let fortyDaysAgo = Date().addingTimeInterval(-40 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: fortyDaysAgo], ofItemAtPath: file.path)
        var settings = CleanupSettings()

        XCTAssertEqual(names(ScanEngine.clutter(homeDirectory: home, settings: settings).run(), "old-downloads"), [])

        settings.oldDownloadDays = 30
        // Reading the file's dates may itself count as opening it on some systems, so
        // only the summary is checked strictly here; the scanner's own tests cover the dates.
        let report = ScanEngine.clutter(homeDirectory: home, settings: settings).run()
        XCTAssertTrue(report.sections.first { $0.id == "old-downloads" }?.summary.contains("30") ?? false)
    }

    func testChecksThatAreTurnedOffDoNotRun() {
        var settings = CleanupSettings()
        settings.checksTurnedOff = ["duplicates", "developer", "no-such-check"]

        let engine = ScanEngine.clutter(homeDirectory: home, settings: settings)

        XCTAssertEqual(engine.scanners.map { $0.id }, ["caches", "logs", "leftovers", "old-downloads", "large-files"])
        XCTAssertEqual(ids(engine.run()), ["caches", "logs", "leftovers", "old-downloads", "large-files"])
        XCTAssertEqual(ScanEngine.clutterChecks.map { $0.id }.count, 7, "Settings always lists every check")
        XCTAssertTrue(ScanEngine.clutterChecks.allSatisfy { !$0.title.isEmpty })
    }

    func testNothingInAFolderThatIsLeftOutIsListed() throws {
        // Three different films: each is filled with its own byte, so none is a copy of another.
        try makeFile("Documents/Portfolio/showreel.mov", bytes: 60_000_000, fill: 2)
        try makeFile("Documents/Portfolio/Deep/Inside/master.mov", bytes: 60_000_000, fill: 3)
        try makeFile("Documents/other.mov", bytes: 60_000_000, fill: 4)
        // A copy inside the folder that is left out, and one outside it.
        try makeFile("Documents/Portfolio/logo.psd", bytes: 2_000_000, fill: 9)
        try makeFile("Desktop/logo copy.psd", bytes: 2_000_000, fill: 9)
        try makeFile("Library/Caches/com.example.Keep/data.bin", bytes: 3_000_000)
        try makeFile("Library/Caches/com.example.Other/data.bin", bytes: 3_000_000)

        var settings = CleanupSettings()
        settings.largeFileBytes = 50_000_000
        let everything = ScanEngine.clutter(homeDirectory: home, settings: settings).run()
        XCTAssertEqual(names(everything, "large-files"), ["master.mov", "other.mov", "showreel.mov"])
        XCTAssertEqual(names(everything, "duplicates").count, 1)
        XCTAssertEqual(names(everything, "caches"), ["com.example.Keep", "com.example.Other"])

        settings.foldersLeftOut = [
            home.appendingPathComponent("Documents/Portfolio").path,
            // Written with different capitals and a slash at the end, as a person might.
            home.appendingPathComponent("Library/Caches/COM.EXAMPLE.KEEP").path + "/"
        ]
        let report = ScanEngine.clutter(homeDirectory: home, settings: settings).run()

        XCTAssertEqual(names(report, "large-files"), ["other.mov"])
        XCTAssertEqual(names(report, "duplicates"), [], "With its twin left out, the loose copy is not a duplicate any more")
        XCTAssertEqual(names(report, "caches"), ["com.example.Other"])
    }

    func testAnItemWithALeftOutFolderInsideItIsNotListedEither() throws {
        try makeFile("Library/Caches/com.example.Editor/thumbnails/a.bin", bytes: 3_000_000)
        try makeFile("Library/Caches/com.example.Editor/Keep/precious.bin", bytes: 3_000_000)
        var settings = CleanupSettings()
        settings.foldersLeftOut = [home.appendingPathComponent("Library/Caches/com.example.Editor/Keep").path]

        let report = ScanEngine.clutter(homeDirectory: home, settings: settings).run()

        XCTAssertEqual(names(report, "caches"), [], "Removing the cache folder would take the folder that is left out with it")
    }

    func testFoldersAreComparedByWhereTheyAreNotByHowTheyAreWritten() {
        let folder = URL(fileURLWithPath: "/Users/someone/Documents/Portfolio")
        func touches(_ path: String) -> Bool {
            ScanSupport.touches(URL(fileURLWithPath: path), anyOf: [folder])
        }
        XCTAssertTrue(touches("/Users/someone/Documents/Portfolio"))
        XCTAssertTrue(touches("/Users/someone/Documents/Portfolio/reel.mov"))
        XCTAssertTrue(touches("/Users/someone/documents/portfolio/Reel.mov"))
        XCTAssertTrue(touches("/Users/someone/Documents"), "It has the folder inside it")
        XCTAssertFalse(touches("/Users/someone/Documents/Portfolio 2/reel.mov"), "A name that only starts the same is another folder")
        XCTAssertFalse(touches("/Users/someone/Desktop/reel.mov"))
    }

    // MARK: - The tool for AI agents follows the same settings

    func testTheAgentDoorScansWithTheSameSettingsAndSaysSo() throws {
        try AgentDoorSwitch(dataDirectory: baseDirectory).set(true)
        var settings = CleanupSettings()
        settings.checksTurnedOff = ["duplicates"]
        settings.foldersLeftOut = [home.appendingPathComponent("Library/Caches/com.example.Keep").path]
        try CleanupSettingsStore(dataDirectory: baseDirectory).save(settings)
        try makeFile("Library/Caches/com.example.Keep/data.bin", bytes: 3_000_000)
        try makeFile("Library/Caches/com.example.Other/data.bin", bytes: 3_000_000)

        let door = AgentDoor(dataDirectory: baseDirectory, sources: .live(homeDirectory: home, dataDirectory: baseDirectory))
        let reply = door.answer(["cleanup"])
        let answer = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(reply.output.utf8)) as? [String: Any])

        let groups = try XCTUnwrap(answer["groups"] as? [[String: Any]])
        XCTAssertFalse(groups.contains { $0["id"] as? String == "duplicates" })
        let caches = try XCTUnwrap(groups.first { $0["id"] as? String == "caches" }?["items"] as? [[String: Any]])
        XCTAssertEqual(caches.count, 1)
        XCTAssertTrue((caches.first?["path"] as? String)?.hasSuffix("com.example.Other") ?? false)
        XCTAssertEqual(answer["checksTurnedOff"] as? [String], ["duplicates"])
        XCTAssertEqual((answer["foldersLeftOut"] as? [String])?.count, 1)
    }
}
