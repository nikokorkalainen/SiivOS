import XCTest
@testable import SiivOSCore

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
        let record = try core.apply(plan)

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
        let record = try core.apply(core.plan(removing: [free, taken], reason: "Test."))
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
        let record = try core.apply(core.plan(removing: [file], reason: "Test."))

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
        let first = try core.apply(core.plan(removing: [try makeFile("Documents/a.txt")], reason: "Test."))
        let second = try core.apply(core.plan(removing: [try makeFile("Documents/b.txt")], reason: "Test."))

        let restartedCore = try makeCore()
        XCTAssertEqual(try restartedCore.history(), [second, first])
    }

    func testUnknownRecordIsReported() throws {
        let core = try makeCore()
        XCTAssertThrowsError(try core.undo(recordID: UUID()))
        XCTAssertThrowsError(try core.deletePermanently(recordID: UUID()))
    }

    // MARK: - When things go wrong

    func testApplyPutsEverythingBackWhenOneItemCannotBeMoved() throws {
        let core = try makeCore()
        let first = try makeFile("Documents/first.txt", contents: "one")
        let second = try makeFile("Documents/second.txt")
        let plan = core.plan(removing: [first, second], reason: "Test.")
        try FileManager.default.removeItem(at: second)

        XCTAssertThrowsError(try core.apply(plan))

        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "one")
        XCTAssertEqual(try core.history(), [])
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
