import XCTest
@testable import SiivOSCore

final class SafetyRulesTests: TemporaryDirectoryTestCase {
    private var holdingDirectory: URL {
        baseDirectory.appendingPathComponent("HoldingArea", isDirectory: true)
    }

    private var rules: SafetyRules {
        SafetyRules(homeDirectory: home, holdingDirectory: holdingDirectory)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        try FileManager.default.createDirectory(at: holdingDirectory, withIntermediateDirectories: true)
    }

    func testOrdinaryFilesMayBeRemoved() throws {
        let document = try makeFile("Documents/old-report.txt")
        let cache = try makeFile("Library/Caches/com.example.app/data.bin")
        let looseFile = try makeFile("notes.txt")

        XCTAssertNil(rules.reasonToRefuse(document))
        XCTAssertNil(rules.reasonToRefuse(cache))
        XCTAssertNil(rules.reasonToRefuse(cache.deletingLastPathComponent()))
        XCTAssertNil(rules.reasonToRefuse(looseFile))
    }

    func testBothSpellingsOfTheMacsPrivateFoldersAreTreatedAlike() {
        // On a Mac, /var, /tmp and /etc are other names for /private/var and so on.
        let pretendHome = URL(fileURLWithPath: "/private/var/folders/ab/home")
        let rules = SafetyRules(
            homeDirectory: pretendHome,
            holdingDirectory: URL(fileURLWithPath: "/private/var/folders/ab/home/Library/Application Support/SiivOS/HoldingArea")
        )

        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/var/folders/ab/home")), "The home folder, spelled the short way")
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/var/folders/ab/home/Library/Application Support/SiivOS/HoldingArea")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/private/var/folders/ab/home/Documents")))
    }

    func testTheDiskAndMacOSAreProtected() {
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/Applications")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/Users")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/System/Library/CoreServices")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/usr/bin/swift")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/usr/local")))
        XCTAssertNotNil(rules.reasonToRefuse(URL(fileURLWithPath: "/bin/sh")))
    }

    func testTheHomeFolderAndItsMainFoldersAreProtected() throws {
        let documents = try makeFolder("Documents")
        let caches = try makeFolder("Library/Caches")

        XCTAssertNotNil(rules.reasonToRefuse(home))
        XCTAssertNotNil(rules.reasonToRefuse(root), "A folder containing the home folder must be refused")
        XCTAssertNotNil(rules.reasonToRefuse(documents))
        XCTAssertNotNil(rules.reasonToRefuse(home.appendingPathComponent("Library", isDirectory: true)))
        XCTAssertNotNil(rules.reasonToRefuse(caches))
    }

    func testProtectionIgnoresUpperAndLowerCase() throws {
        try makeFolder("Documents")
        let differentCase = home.appendingPathComponent("documents", isDirectory: true)
        XCTAssertNotNil(rules.reasonToRefuse(differentCase))
    }

    func testTheHoldingAreaAndSiivOSDataAreProtected() {
        let heldFile = holdingDirectory.appendingPathComponent("some-id/file.txt")

        XCTAssertNotNil(rules.reasonToRefuse(heldFile))
        XCTAssertNotNil(rules.reasonToRefuse(holdingDirectory))
        XCTAssertNotNil(rules.reasonToRefuse(baseDirectory))
    }
}

final class PermissionsTests: TemporaryDirectoryTestCase {
    func testFullDiskAccessIsJudgedByWhetherTheProtectedFileCanBeOpened() throws {
        XCTAssertFalse(Permissions.hasFullDiskAccess(homeDirectory: home), "Nothing to open means no access")

        try makeFile("Library/Application Support/com.apple.TCC/TCC.db")
        XCTAssertTrue(Permissions.hasFullDiskAccess(homeDirectory: home))
    }
}
