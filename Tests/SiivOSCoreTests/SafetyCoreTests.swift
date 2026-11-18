import XCTest
@testable import SiivOSCore

/// A file manager that can be told to fail when one folder is created, to stand in for
/// a disk that is full or a folder that may not be written to.
private final class FailingFileManager: FileManager, @unchecked Sendable {
    var folderThatCannotBeCreated: URL?

    override func createDirectory(
        at url: URL,
        withIntermediateDirectories createIntermediates: Bool,
        attributes: [FileAttributeKey: Any]? = nil
    ) throws {
        if let blocked = folderThatCannotBeCreated, url.standardizedFileURL.path == blocked.standardizedFileURL.path {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

final class SafetyCoreTests: TemporaryDirectoryTestCase {
    private func makeCore() throws -> SafetyCore {
        try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
    }

    private func names(_ items: [RemovalPlan.Item]) -> [String] {
        items.map { $0.url.lastPathComponent }.sorted()
    }

    // MARK: - Planning

    func testPlanningChangesNothingAndExplainsWhatWillHappen() throws {
        let core = try makeCore()
        let file = try makeFile("Documents/old.txt")

        let plan = core.plan(removing: [file], reason: "You chose this item yourself.")

        XCTAssertTrue(exists(file))
        XCTAssertEqual(names(plan.items), ["old.txt"])
        XCTAssertTrue(plan.refused.isEmpty)
        XCTAssertEqual(plan.title, "Removed old.txt")
        XCTAssertTrue(plan.explanation.contains("You chose this item yourself."))
        XCTAssertTrue(plan.explanation.contains("holding area"))
        XCTAssertGreaterThan(plan.totalBytes, 0)
        XCTAssertEqual(try core.history(), [])
    }

    func testPlanRefusesProtectedAndMissingItems() throws {
        let core = try makeCore()
        let file = try makeFile("Documents/old.txt")
        let documents = home.appendingPathComponent("Documents", isDirectory: true)
        let missing = home.appendingPathComponent("Documents/gone.txt")

        let plan = core.plan(removing: [file, documents, missing], reason: "Test.")

        XCTAssertEqual(names(plan.items), ["old.txt"])
        XCTAssertEqual(plan.refused.count, 2)
    }

    func testPlanCountsAnItemInsideAChosenFolderOnlyOnce() throws {
        let core = try makeCore()
        let inner = try makeFile("Documents/Project/inner.txt")
        let folder = home.appendingPathComponent("Documents/Project", isDirectory: true)

        let plan = core.plan(removing: [inner, folder, folder], reason: "Test.")

        XCTAssertEqual(names(plan.items), ["Project"])
        XCTAssertTrue(plan.refused.isEmpty)
    }

    func testAPlanWithNothingAllowedCannotBeApplied() throws {
        let core = try makeCore()
        let plan = core.plan(removing: [home], reason: "Test.")

        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertThrowsError(try core.apply(plan))
        XCTAssertEqual(try core.history(), [])
    }

    // MARK: - Removing and putting back

    func testApplyMovesItemsAndUndoPutsThemBack() throws {
        let core = try makeCore()
        let first = try makeFile("Documents/first.txt", contents: "one")
        let second = try makeFile("Downloads/second.txt", contents: "two")

        let plan = core.plan(removing: [first, second], reason: "Test.")
        let applied = try core.apply(plan)
        let record = applied.record

        XCTAssertTrue(applied.failures.isEmpty)
        XCTAssertFalse(exists(first))
        XCTAssertFalse(exists(second))
        XCTAssertEqual(record.title, "Removed 2 items")
        XCTAssertEqual(record.explanation, plan.explanation)
        XCTAssertEqual(record.count(of: .held), 2)
        XCTAssertEqual(try core.history(), [record])

        let result = try core.undo(recordID: record.id)

        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.record.count(of: .restored), 2)
        XCTAssertFalse(result.record.canUndo)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "two")
        XCTAssertEqual(try core.history(), [result.record])
    }

    func testUndoKeepsAnItemHeldWhenItsPlaceIsTaken() throws {
        let core = try makeCore()
        let free = try makeFile("Documents/free.txt", contents: "old free")
        let taken = try makeFile("Documents/taken.txt", contents: "old taken")
        let record = try core.apply(core.plan(removing: [free, taken], reason: "Test.")).record
        try makeFile("Documents/taken.txt", contents: "new")

        let result = try core.undo(recordID: record.id)

        XCTAssertEqual(result.failures.count, 1)
        XCTAssertEqual(result.record.count(of: .restored), 1)
        XCTAssertEqual(result.record.count(of: .held), 1)
        XCTAssertTrue(result.record.canUndo)
        XCTAssertEqual(try String(contentsOf: free, encoding: .utf8), "old free")
        XCTAssertEqual(try String(contentsOf: taken, encoding: .utf8), "new")

        // Once the place is free again, the rest can be put back.
        try FileManager.default.removeItem(at: taken)
        let secondResult = try core.undo(recordID: record.id)
        XCTAssertTrue(secondResult.failures.isEmpty)
        XCTAssertEqual(try String(contentsOf: taken, encoding: .utf8), "old taken")
    }

    func testDeletingPermanentlyCannotBeUndone() throws {
        let core = try makeCore()
        let file = try makeFile("Documents/old.txt")
        let record = try core.apply(core.plan(removing: [file], reason: "Test.")).record

        let deleted = try core.deletePermanently(recordID: record.id)
        XCTAssertTrue(deleted.failures.isEmpty)
        XCTAssertEqual(deleted.record.count(of: .deleted), 1)
        XCTAssertEqual(deleted.record.heldBytes, 0)

        let undone = try core.undo(recordID: record.id)
        XCTAssertEqual(undone.record.count(of: .deleted), 1)
        XCTAssertFalse(exists(file))
    }

    func testHistoryIsNewestFirstAndSurvivesARestart() throws {
        let core = try makeCore()
        let first = try core.apply(core.plan(removing: [try makeFile("Documents/a.txt")], reason: "Test.")).record
        let second = try core.apply(core.plan(removing: [try makeFile("Documents/b.txt")], reason: "Test.")).record

        let restartedCore = try makeCore()
        XCTAssertEqual(try restartedCore.history(), [second, first])
    }

    func testUnknownRecordIsReported() throws {
        let core = try makeCore()
        XCTAssertThrowsError(try core.undo(recordID: UUID()))
        XCTAssertThrowsError(try core.deletePermanently(recordID: UUID()))
    }

    // MARK: - When things go wrong

    func testApplyMovesWhatItCanAndReportsTheRest() throws {
        let core = try makeCore()
        let first = try makeFile("Documents/first.txt")
        let second = try makeFile("Documents/second.txt")
        let plan = core.plan(removing: [first, second], reason: "Test.")
        try FileManager.default.removeItem(at: second)

        let result = try core.apply(plan)

        XCTAssertFalse(exists(first))
        XCTAssertEqual(result.record.items.count, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(result.failures[0].path.hasSuffix("second.txt"))
        XCTAssertEqual(try core.history(), [result.record])
    }

    func testApplyFailsWhenNothingCouldBeMoved() throws {
        let core = try makeCore()
        let file = try makeFile("Documents/only.txt")
        let plan = core.plan(removing: [file], reason: "Test.")
        try FileManager.default.removeItem(at: file)

        XCTAssertThrowsError(try core.apply(plan))
        XCTAssertEqual(try core.history(), [])
    }

    func testARequiredItemThatCannotBeMovedLeavesEverythingInPlace() throws {
        let core = try makeCore()
        let leftover = try makeFile("Library/Caches/com.example.app/data.bin")
        let app = try makeFile("Documents/the-app-itself.txt")
        let plan = core.plan(removing: [leftover, app], reason: "Test.", required: [app])
        XCTAssertEqual(plan.items.count, 2)
        try FileManager.default.removeItem(at: app)

        XCTAssertThrowsError(try core.apply(plan))

        XCTAssertTrue(exists(leftover), "What was already moved is put back when the change cannot go through")
        XCTAssertEqual(try core.history(), [])
    }

    func testAChangeThatCannotBeWrittenDownIsPutBack() throws {
        let files = FailingFileManager()
        let core = try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home, fileManager: files)
        let file = try makeFile("Documents/keep-track-of-me.txt")
        let plan = core.plan(removing: [file], reason: "Test.")
        // Saving the history starts by making sure its folder is there.
        files.folderThatCannotBeCreated = baseDirectory

        XCTAssertThrowsError(try core.apply(plan))

        XCTAssertTrue(exists(file), "A change that is not in the history could never be undone, so it must not stay")
        files.folderThatCannotBeCreated = nil
        XCTAssertEqual(try core.history(), [])
    }

    func testErrorsSayWhatWentWrongInPlainWords() {
        let unreadable = ActionLogError.unreadable(path: "/tmp/action-log.json", reason: "broken")
        XCTAssertTrue(unreadable.errorDescription?.contains("/tmp/action-log.json") ?? false)
        XCTAssertTrue(unreadable.errorDescription?.contains("Nothing was changed") ?? false)
        XCTAssertTrue(HoldingAreaError.heldCopyMissing("/Users/x/a.txt").errorDescription?.contains("/Users/x/a.txt") ?? false)
        XCTAssertNotNil(SafetyCoreError.recordNotFound.errorDescription)
    }

    func testADamagedHistoryStopsARemovalBeforeAnythingMoves() throws {
        let core = try makeCore()
        let file = try makeFile("Documents/old.txt")
        let plan = core.plan(removing: [file], reason: "Test.")
        try Data("this is not json".utf8).write(to: core.logFileURL)

        XCTAssertThrowsError(try core.apply(plan))
        XCTAssertTrue(exists(file))
    }
}
