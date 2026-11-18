import XCTest
@testable import SiivOSCore

final class ClutterScannerTests: TemporaryDirectoryTestCase {
    private func names(_ findings: [Finding]) -> [String] {
        findings.map { $0.url.lastPathComponent }.sorted()
    }

    // MARK: - Caches and logs

    // Sizes on disk are rounded up, and by different amounts on a Mac and on Linux, so the
    // "big" and "tiny" items in these tests are far apart: 500 KB against a few bytes.

    func testCachesScannerReportsSizeableCachesButNotApplesOrTinyOnes() throws {
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)
        try makeFile("Library/Caches/com.example.Tiny/data.bin", bytes: 10)
        try makeFile("Library/Caches/com.apple.Safari/data.bin", bytes: 500_000)

        let findings = try CachesScanner(homeDirectory: home, minimumBytes: 200_000).scan()

        XCTAssertEqual(names(findings), ["com.example.Browser"])
        XCTAssertGreaterThanOrEqual(findings[0].sizeBytes, 500_000)
    }

    func testLogsScannerReportsSizeableLogs() throws {
        try makeFile("Library/Logs/Example/app.log", bytes: 500_000)
        try makeFile("Library/Logs/small.log", bytes: 10)

        let findings = try LogsScanner(homeDirectory: home, minimumBytes: 200_000).scan()

        XCTAssertEqual(names(findings), ["Example"])
    }

    // MARK: - Labels

    func testCachesAndLogsAreLabelledSafeToRemove() throws {
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)
        try makeFile("Library/Logs/Example/app.log", bytes: 500_000)

        let caches = try CachesScanner(homeDirectory: home, minimumBytes: 200_000).scan()
        let logs = try LogsScanner(homeDirectory: home, minimumBytes: 200_000).scan()

        XCTAssertEqual(caches.map { $0.safety }, [.safeToRemove])
        XCTAssertEqual(logs.map { $0.safety }, [.safeToRemove])
        XCTAssertTrue((caches + logs).allSatisfy { !$0.safetyReason.isEmpty })
        XCTAssertEqual(Finding.Safety.safeToRemove.title, "Safe to remove")
        XCTAssertEqual(Finding.Safety.checkFirst.title, "Check first")
    }

    func testYourOwnFilesAreAlwaysLabelledCheckFirst() throws {
        try makeFile("Downloads/old-installer.dmg", bytes: 100)
        try makeFile("Movies/holiday.mov", bytes: 50_000)
        try makeFile("Pictures/photo.jpg", bytes: 5_000, fill: 7)
        try makeFile("Pictures/photo copy.jpg", bytes: 5_000, fill: 7)
        let later = Date().addingTimeInterval(100 * 86_400)

        let findings = try OldDownloadsScanner(homeDirectory: home, olderThanDays: 90, now: later).scan()
            + LargeFilesScanner(homeDirectory: home, minimumBytes: 40_000).scan()
            + DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan()

        XCTAssertEqual(names(findings), ["holiday.mov", "old-installer.dmg", "photo copy.jpg"])
        XCTAssertTrue(findings.allSatisfy { $0.safety == .checkFirst })
        XCTAssertTrue(findings.allSatisfy { !$0.safetyReason.isEmpty })
    }

    func testLeftoversThatCanHoldYourWorkAreLabelledCheckFirst() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Application Support/com.gone.Tool/projects.db", bytes: 500_000)
        try makeFile("Library/Containers/com.gone.Tool/Data/Documents/drawing.bin", bytes: 500_000)
        try makeFile("Library/Saved Application State/com.gone.Tool.savedState/window.data", bytes: 500_000)
        try makeFile("Library/HTTPStorages/com.gone.Tool/cookies.bin", bytes: 500_000)

        let findings = try LeftoversScanner(
            homeDirectory: home,
            applicationDirectories: [applications],
            minimumBytes: 200_000
        ).scan()
        var labels: [String: Finding.Safety] = [:]
        for finding in findings {
            labels[finding.url.deletingLastPathComponent().lastPathComponent] = finding.safety
        }

        XCTAssertEqual(labels, [
            "Application Support": .checkFirst,
            "Containers": .checkFirst,
            "Saved Application State": .safeToRemove,
            "HTTPStorages": .safeToRemove
        ])
        XCTAssertTrue(findings.allSatisfy { !$0.safetyReason.isEmpty })
    }

    func testScannersFindNothingWhenTheirFolderIsMissing() throws {
        XCTAssertEqual(try CachesScanner(homeDirectory: home).scan(), [])
        XCTAssertEqual(try LogsScanner(homeDirectory: home).scan(), [])
        XCTAssertEqual(try OldDownloadsScanner(homeDirectory: home).scan(), [])
        XCTAssertEqual(try LargeFilesScanner(homeDirectory: home).scan(), [])
        XCTAssertEqual(try DuplicateFilesScanner(homeDirectory: home).scan(), [])
    }

    // MARK: - Old downloads

    func testOldDownloadsScannerReportsOnlyItemsLeftUntouched() throws {
        try makeFile("Downloads/old-installer.dmg", bytes: 100)
        let recent = try makeFile("Downloads/recent.pdf", bytes: 100)
        // Pretend it is 100 days from now, and that one file was changed 5 days before that.
        let pretendNow = Date().addingTimeInterval(100 * 86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: pretendNow.addingTimeInterval(-5 * 86_400)],
            ofItemAtPath: recent.path
        )

        let scanner = OldDownloadsScanner(homeDirectory: home, olderThanDays: 90, now: pretendNow)
        let findings = try scanner.scan()

        XCTAssertEqual(names(findings), ["old-installer.dmg"])
        XCTAssertTrue(findings[0].explanation.hasPrefix("Not opened or changed since"))
    }

    func testNothingInDownloadsIsOldRightAfterItArrives() throws {
        try makeFile("Downloads/new.zip", bytes: 100)
        XCTAssertEqual(try OldDownloadsScanner(homeDirectory: home).scan(), [])
    }

    // MARK: - Large files

    func testLargeFilesScannerReportsBigFilesInUserFolders() throws {
        try makeFile("Movies/holiday.mov", bytes: 50_000)
        try makeFile("Documents/Deep/Folder/archive.zip", bytes: 60_000)
        try makeFile("Documents/letter.txt", bytes: 100)
        try makeFile("Documents/.hidden-big.bin", bytes: 50_000)
        try makeFile("Library/Caches/not-a-user-folder.bin", bytes: 50_000)

        let findings = try LargeFilesScanner(homeDirectory: home, minimumBytes: 40_000).scan()

        XCTAssertEqual(names(findings), ["archive.zip", "holiday.mov"])
    }

    func testFilesInsideLibrariesAreNeverPickedOut() throws {
        // A photo that is also inside a photo library, and a big film inside a video
        // library. The libraries are plain folders here, as they are on a Mac where
        // the app that owns them is not installed.
        try makeFile("Desktop/photo.cr2", bytes: 50_000, fill: 7)
        try makeFile("Pictures/Lightroom Library.lrlibrary/originals/2022/photo.cr2", bytes: 50_000, fill: 7)
        try makeFile("Pictures/Photos Library.photoslibrary/originals/A/photo.heic", bytes: 50_000, fill: 7)
        try makeFile("Movies/Film.fcpbundle/Original Media/clip.mov", bytes: 60_000)

        let duplicates = try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan()
        let large = try LargeFilesScanner(homeDirectory: home, minimumBytes: 40_000).scan()

        XCTAssertEqual(duplicates, [], "A copy inside a library is not offered, and neither is the loose one")
        XCTAssertEqual(names(large), ["photo.cr2"])
        XCTAssertEqual(large.first?.url.deletingLastPathComponent().lastPathComponent, "Desktop")
    }

    // MARK: - Duplicates

    func testDuplicateScannerKeepsOneCopyAndReportsTheOthers() throws {
        try makeFile("Pictures/photo.jpg", bytes: 5_000, fill: 7)
        try makeFile("Pictures/photo copy.jpg", bytes: 5_000, fill: 7)
        try makeFile("Downloads/Unsorted/photo (1).jpg", bytes: 5_000, fill: 7)
        try makeFile("Pictures/different.jpg", bytes: 5_000, fill: 8)
        try makeFile("Pictures/other-size.jpg", bytes: 6_000, fill: 7)

        let findings = try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan()

        XCTAssertEqual(names(findings), ["photo (1).jpg", "photo copy.jpg"])
        XCTAssertTrue(findings.allSatisfy { $0.explanation.contains("/Pictures/photo.jpg") })
    }

    func testFilesThatDifferOnlyAtTheEndAreNotDuplicates() throws {
        // Longer than the part that is compared first, so the full comparison is what tells them apart.
        try makeFile("Documents/a.bin", bytes: 200_000, fill: 3)
        try makeFile("Documents/b.bin", bytes: 200_000, fill: 3, ending: 9)

        XCTAssertEqual(try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan(), [])
    }

    func testLargeIdenticalFilesAreDuplicates() throws {
        try makeFile("Documents/a.bin", bytes: 200_000, fill: 3)
        try makeFile("Documents/b.bin", bytes: 200_000, fill: 3)

        let findings = try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan()
        XCTAssertEqual(names(findings), ["b.bin"])
    }

    func testTwoNamesForTheSameFileAreNotDuplicates() throws {
        let original = try makeFile("Documents/original.bin", bytes: 5_000)
        let secondName = home.appendingPathComponent("Documents/second-name.bin")
        try FileManager.default.linkItem(at: original, to: secondName)

        XCTAssertEqual(try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan(), [])
    }

    func testSmallFilesAreNotComparedForDuplicates() throws {
        try makeFile("Documents/a.txt", bytes: 100)
        try makeFile("Documents/b.txt", bytes: 100)

        XCTAssertEqual(try DuplicateFilesScanner(homeDirectory: home, minimumBytes: 1_000).scan(), [])
    }

    // MARK: - Installed apps and leftovers

    func testInstalledAppsAreFoundWithTheirIdentifiers() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeApp("Utilities/Disk Tool.app", identifier: "org.sample.DiskTool")
        try makeApp("Broken.app", identifier: nil)
        try FileManager.default.createDirectory(
            at: applications.appendingPathComponent("Not An App", isDirectory: true),
            withIntermediateDirectories: true
        )

        let apps = InstalledApps.find(in: [applications, root.appendingPathComponent("Missing")])
        let identifiers = Dictionary(uniqueKeysWithValues: apps.map { ($0.name, $0.bundleIdentifier) })

        XCTAssertEqual(apps.count, 3)
        XCTAssertEqual(identifiers["Notes"], "com.example.Notes")
        XCTAssertEqual(identifiers["Disk Tool"], "org.sample.DiskTool")
        XCTAssertEqual(identifiers["Broken"], .some(nil))
    }

    func testLeftoversScannerReportsOnlyDataFromDevelopersWithNoInstalledApp() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Application Support/com.gone.Tool/data.bin", bytes: 500_000)
        try makeFile("Library/Saved Application State/com.gone.Tool.savedState/window.data", bytes: 500_000)
        // Same developer as an installed app, so it may still be in use.
        try makeFile("Library/Application Support/com.example.Helper/data.bin", bytes: 500_000)
        // Not named after an app identifier, so SiivOS cannot tell whose it is.
        try makeFile("Library/Application Support/Some App/data.bin", bytes: 500_000)
        try makeFile("Library/Application Support/com.apple.Something/data.bin", bytes: 500_000)
        try makeFile("Library/Application Support/com.gone.Tiny/data.bin", bytes: 10)
        try makeFile("Library/Saved Application State/com.gone.Other/window.data", bytes: 500_000)

        let scanner = LeftoversScanner(
            homeDirectory: home,
            applicationDirectories: [applications],
            minimumBytes: 200_000
        )
        let findings = try scanner.scan()

        XCTAssertEqual(names(findings), ["com.gone.Tool", "com.gone.Tool.savedState"])
    }

    func testLeftoversScannerReportsNothingWhenNoAppsCanBeFound() throws {
        try makeFile("Library/Application Support/com.gone.Tool/data.bin", bytes: 500_000)

        let scanner = LeftoversScanner(
            homeDirectory: home,
            applicationDirectories: [applications],
            minimumBytes: 200_000
        )
        XCTAssertEqual(try scanner.scan(), [])
    }

    func testAppIdentifierShapes() {
        XCTAssertTrue(LeftoversScanner.looksLikeAppIdentifier("com.example.Notes"))
        XCTAssertTrue(LeftoversScanner.looksLikeAppIdentifier("org.sample-dev.My_App2.helper"))
        XCTAssertFalse(LeftoversScanner.looksLikeAppIdentifier("Some App"))
        XCTAssertFalse(LeftoversScanner.looksLikeAppIdentifier("example.Notes"))
        XCTAssertFalse(LeftoversScanner.looksLikeAppIdentifier("com..Notes"))
        XCTAssertFalse(LeftoversScanner.looksLikeAppIdentifier("2com.example.Notes"))
        XCTAssertEqual(LeftoversScanner.developer(of: "COM.Example.Notes"), "com.example")
        XCTAssertNil(LeftoversScanner.developer(of: "Notes"))
    }

    // MARK: - Working together with the safety core

    func testEveryFindingOfTheCleanupScanCanBeRemovedAndPutBack() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 2_000_000)
        try makeFile("Library/Logs/Example/app.log", bytes: 2_000_000)
        try makeFile("Documents/copy-a.bin", bytes: 1_500_000, fill: 4)
        try makeFile("Documents/copy-b.bin", bytes: 1_500_000, fill: 4)
        try makeFile("Library/Developer/Xcode/DerivedData/Project-abc/build.bin", bytes: 20_000_000)

        let engine = ScanEngine(scanners: [
            CachesScanner(homeDirectory: home),
            LogsScanner(homeDirectory: home),
            LeftoversScanner(homeDirectory: home, applicationDirectories: [applications]),
            DeveloperClutterScanner(homeDirectory: home),
            OldDownloadsScanner(homeDirectory: home),
            LargeFilesScanner(homeDirectory: home),
            DuplicateFilesScanner(homeDirectory: home)
        ])
        var titles: [String] = []
        let report = engine.run { titles.append($0) }

        XCTAssertEqual(titles.count, 7)
        XCTAssertTrue(report.sections.allSatisfy { $0.failure == nil })
        let urls = report.sections.flatMap { $0.findings }.map { $0.url }
        XCTAssertEqual(urls.map { $0.lastPathComponent }.sorted(), ["DerivedData", "Example", "com.example.Browser", "copy-b.bin"])

        let core = try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
        let plan = core.plan(removing: urls, title: "Cleaned up", reason: "Test.")
        XCTAssertTrue(plan.refused.isEmpty)
        XCTAssertEqual(report.removingFindingsNoLongerOnDisk().findingCount, 4)

        let result = try core.apply(plan)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(urls.allSatisfy { !exists($0) })

        let remaining = report.removingFindingsNoLongerOnDisk()
        XCTAssertEqual(remaining.findingCount, 0)
        XCTAssertEqual(remaining.sections.count, 7)

        let undone = try core.undo(recordID: result.record.id)
        XCTAssertTrue(undone.failures.isEmpty)
        XCTAssertTrue(urls.allSatisfy { exists($0) })
    }

    func testTheStandardCleanupScanHasSevenDistinctScanners() {
        let engine = ScanEngine.clutter(homeDirectory: home)
        XCTAssertEqual(
            engine.scanners.map { $0.id },
            ["caches", "logs", "leftovers", "developer", "old-downloads", "large-files", "duplicates"]
        )
    }

    // MARK: - Developer tools

    func testDeveloperToolsDataIsFoundByNameWithItsOwnLabel() throws {
        try makeFile("Library/Developer/Xcode/DerivedData/Project-abc/build.bin", bytes: 20_000_000)
        try makeFile("Library/Developer/Xcode/Archives/2026-01-01/App.xcarchive/app.bin", bytes: 20_000_000)
        try makeFile("Library/Developer/Xcode/iOS DeviceSupport/19.0/symbols.bin", bytes: 20_000_000)
        try makeFile(".npm/_cacache/content/package.tgz", bytes: 20_000_000)
        try makeFile("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", bytes: 20_000_000)
        // Too small to be worth listing.
        try makeFile(".gradle/caches/tiny.bin", bytes: 10)

        let findings = try DeveloperClutterScanner(homeDirectory: home).scan()
        var labels: [String: Finding.Safety] = [:]
        for finding in findings {
            labels[finding.displayName ?? "?"] = finding.safety
        }

        XCTAssertEqual(labels, [
            "Xcode build results": .safeToRemove,
            "Xcode archives": .checkFirst,
            "Xcode device files (iOS)": .safeToRemove,
            "npm packages": .safeToRemove,
            "Docker's disk": .checkFirst
        ])
        XCTAssertTrue(findings.allSatisfy { !$0.explanation.isEmpty && !$0.safetyReason.isEmpty })
        XCTAssertTrue(findings.allSatisfy { $0.heldBackReason == nil })
        XCTAssertEqual(findings.first { $0.displayName == "Xcode build results" }?.url.lastPathComponent, "DerivedData")
    }

    func testDeveloperToolsDataIsHeldBackWhileItsToolIsOpen() throws {
        try makeFile("Library/Developer/Xcode/DerivedData/Project-abc/build.bin", bytes: 20_000_000)
        try makeFile(".npm/_cacache/content/package.tgz", bytes: 20_000_000)

        let findings = try DeveloperClutterScanner(
            homeDirectory: home,
            runningApps: [RunningApp(name: "Xcode", bundleIdentifier: "com.apple.dt.Xcode")]
        ).scan()

        let derived = findings.first { $0.displayName == "Xcode build results" }
        XCTAssertEqual(derived?.heldBackReason, "Xcode is open. Quit it, then scan again.")
        XCTAssertNil(findings.first { $0.displayName == "npm packages" }?.heldBackReason)
    }

    func testAMacWithoutDeveloperToolsHasNothingToShow() throws {
        try makeFile("Documents/letter.txt", bytes: 100)
        XCTAssertEqual(try DeveloperClutterScanner(homeDirectory: home).scan(), [])
    }
}
