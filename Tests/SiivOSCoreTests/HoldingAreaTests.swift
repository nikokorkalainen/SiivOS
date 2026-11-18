import XCTest
@testable import SiivOSCore

final class HoldingAreaTests: TemporaryDirectoryTestCase {
    private var holdingArea: HoldingArea {
        HoldingArea(directory: baseDirectory.appendingPathComponent("HoldingArea", isDirectory: true))
    }

    func testHoldingMovesTheFileAndRestoringPutsItBack() throws {
        let file = try makeFile("Documents/report.txt", contents: "important")

        let item = try holdingArea.hold(file)
        XCTAssertFalse(exists(file))
        XCTAssertTrue(holdingArea.contains(item))
        XCTAssertEqual(item.name, "report.txt")
        XCTAssertGreaterThan(item.sizeBytes, 0)

        try holdingArea.restore(item)
        XCTAssertFalse(holdingArea.contains(item))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "important")
    }

    func testFolderIsHeldWithEverythingInsideIt() throws {
        try makeFile("Documents/Project/notes.txt", contents: "one")
        let nested = try makeFile("Documents/Project/Assets/logo.txt", contents: "two")
        let folder = home.appendingPathComponent("Documents/Project", isDirectory: true)

        let item = try holdingArea.hold(folder)
        XCTAssertFalse(exists(folder))

        try holdingArea.restore(item)
        XCTAssertEqual(try String(contentsOf: nested, encoding: .utf8), "two")
    }

    func testItemsWithTheSameNameAreKeptApart() throws {
        let first = try makeFile("A/same.txt", contents: "first")
        let second = try makeFile("B/same.txt", contents: "second")

        let firstItem = try holdingArea.hold(first)
        let secondItem = try holdingArea.hold(second)
        try holdingArea.restore(secondItem)
        try holdingArea.restore(firstItem)

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "second")
    }

    func testRestoreRecreatesAMissingParentFolder() throws {
        let file = try makeFile("Old/Deep/file.txt")
        let item = try holdingArea.hold(file)
        try FileManager.default.removeItem(at: home.appendingPathComponent("Old", isDirectory: true))

        try holdingArea.restore(item)
        XCTAssertTrue(exists(file))
    }

    func testRestoreNeverOverwritesSomethingNew() throws {
        let file = try makeFile("Documents/report.txt", contents: "old")
        let item = try holdingArea.hold(file)
        try makeFile("Documents/report.txt", contents: "new")

        XCTAssertThrowsError(try holdingArea.restore(item))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "new")
        XCTAssertTrue(holdingArea.contains(item))
    }

    func testHoldingAMissingItemFails() {
        let missing = home.appendingPathComponent("nothing-here.txt")
        XCTAssertThrowsError(try holdingArea.hold(missing))
    }

    func testALinkIsHeldWithoutTouchingWhatItPointsTo() throws {
        let target = try makeFile("Documents/target.txt", contents: "target")
        let link = home.appendingPathComponent("Documents/link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let item = try holdingArea.hold(link)
        XCTAssertFalse(exists(link))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target")

        try holdingArea.restore(item)
        XCTAssertTrue(exists(link))
    }

    func testDeletingPermanentlyRemovesTheHeldCopy() throws {
        let file = try makeFile("Documents/report.txt")
        let item = try holdingArea.hold(file)

        try holdingArea.deletePermanently(item)
        XCTAssertFalse(holdingArea.contains(item))
        XCTAssertFalse(exists(file))
        XCTAssertThrowsError(try holdingArea.restore(item))

        // Deleting something that is already gone is not an error.
        XCTAssertNoThrow(try holdingArea.deletePermanently(item))
    }
}
