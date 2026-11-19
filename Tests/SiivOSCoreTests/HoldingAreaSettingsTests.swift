import XCTest
@testable import SiivOSCore

final class HoldingAreaSettingsTests: TemporaryDirectoryTestCase {
    private let day: TimeInterval = 86_400

    private func makeCore() throws -> SafetyCore {
        try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
    }

    private func store() -> HoldingAreaSettingsStore {
        HoldingAreaSettingsStore(dataDirectory: baseDirectory)
    }

    /// Removes a file through the safety core, as the app does.
    @discardableResult
    private func remove(_ name: String, with core: SafetyCore) throws -> ActionRecord {
        let file = try makeFile("Documents/" + name, bytes: 300_000)
        return try core.apply(core.plan(removing: [file], reason: "Test.")).record
    }

    // MARK: - Settings

    func testNothingIsEverDeletedUnlessATimeIsChosen() throws {
        let settings = HoldingAreaSettings()
        XCTAssertEqual(settings.deleteAfterDays, 0, "Never, until the user chooses otherwise")
        XCTAssertEqual(settings.warnAboveBytes, 10_000_000_000)
        XCTAssertNil(settings.lastEmptying)

        let core = try makeCore()
        try remove("old.bin", with: core)

        // Even a hundred years later, with no time chosen, nothing is deleted.
        let later = Date().addingTimeInterval(36_500 * day)
        XCTAssertNil(try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: later))
        XCTAssertEqual(try core.history().first?.count(of: .held), 1)
    }

    func testSettingsAreKeptAndOddOnesFallBackToNeverDeleting() throws {
        var settings = HoldingAreaSettings()
        settings.deleteAfterDays = 90
        settings.warnAboveBytes = 5_000_000_000
        try store().save(settings)
        XCTAssertEqual(store().load(), settings)

        // A time that is not among the choices must never be acted on.
        try Data(#"{"deleteAfterDays": 1, "warnAboveBytes": 7}"#.utf8).write(to: store().fileURL)
        XCTAssertEqual(store().load().deleteAfterDays, 0)
        XCTAssertEqual(store().load().warnAboveBytes, 10_000_000_000)

        try Data("not json".utf8).write(to: store().fileURL)
        XCTAssertEqual(store().load(), HoldingAreaSettings())
    }

    func testTheHoldingAreaIsPointedOutOnlyPastTheChosenSize() {
        var settings = HoldingAreaSettings()
        XCTAssertFalse(settings.isWorthPointingOut(heldBytes: 9_000_000_000))
        XCTAssertFalse(settings.isWorthPointingOut(heldBytes: 10_000_000_000))
        XCTAssertTrue(settings.isWorthPointingOut(heldBytes: 10_000_000_001))

        settings.warnAboveBytes = 0
        XCTAssertFalse(settings.isWorthPointingOut(heldBytes: 900_000_000_000), "Never means never")
    }

    // MARK: - Emptying

    func testOnlyWhatHasWaitedLongEnoughIsDeleted() throws {
        let core = try makeCore()
        let record = try remove("old.bin", with: core)
        var settings = HoldingAreaSettings()
        settings.deleteAfterDays = 30
        try store().save(settings)

        // After 29 days nothing happens.
        XCTAssertNil(try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: record.date.addingTimeInterval(29 * day)))
        XCTAssertEqual(try core.history().first?.count(of: .held), 1)
        XCTAssertEqual(try core.heldItems(removedBefore: record.date.addingTimeInterval(-1)).itemCount, 0)

        // After 31 days the item is deleted for good, and a note is left about it.
        let emptying = try XCTUnwrap(try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: record.date.addingTimeInterval(31 * day)))
        XCTAssertEqual(emptying.itemCount, 1)
        XCTAssertGreaterThanOrEqual(emptying.bytes, 300_000)
        XCTAssertEqual(emptying.afterDays, 30)
        XCTAssertEqual(try core.history().first?.count(of: .deleted), 1)
        XCTAssertEqual(try core.history().first?.heldBytes, 0)
        XCTAssertEqual(store().load().lastEmptying, emptying)

        // Running it again deletes nothing more.
        XCTAssertNil(try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: record.date.addingTimeInterval(40 * day)))
    }

    func testNewerChangesAndItemsPutBackAreLeftAlone() throws {
        let core = try makeCore()
        let putBack = try remove("put-back.bin", with: core)
        let old = try remove("old.bin", with: core)
        _ = try core.undo(recordID: putBack.id)
        let restored = home.appendingPathComponent("Documents/put-back.bin")

        let waiting = try core.heldItems(removedBefore: old.date.addingTimeInterval(1))
        XCTAssertEqual(waiting.itemCount, 1, "Only what is still held counts")

        let result = try core.deleteHeldItems(removedBefore: old.date.addingTimeInterval(1))
        XCTAssertEqual(result.itemCount, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(exists(restored), "A file that was put back is not in the holding area and is never touched")

        // A change made after the cutoff stays held.
        let recent = try remove("recent.bin", with: core)
        let nothing = try core.deleteHeldItems(removedBefore: recent.date.addingTimeInterval(-1))
        XCTAssertEqual(nothing.itemCount, 0)
        XCTAssertEqual(try core.history().first { $0.id == recent.id }?.count(of: .held), 1)
        XCTAssertTrue((try core.undo(recordID: recent.id)).failures.isEmpty, "And it can still be put back")
    }

    func testNotesAboutEmptyingsAddUpUntilTheyAreSeen() throws {
        let core = try makeCore()
        var settings = HoldingAreaSettings()
        settings.deleteAfterDays = 30
        try store().save(settings)

        let first = try remove("first.bin", with: core)
        _ = try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: first.date.addingTimeInterval(31 * day))
        let second = try remove("second.bin", with: core)
        let total = try XCTUnwrap(try HoldingAreaKeeper.emptyIfDue(core: core, store: store(), now: second.date.addingTimeInterval(31 * day)))

        XCTAssertEqual(total.itemCount, 2, "Both emptyings, since the first note was never seen")

        // Once the note has been seen and cleared, the settings themselves are untouched.
        var seen = store().load()
        seen.lastEmptying = nil
        try store().save(seen)
        XCTAssertEqual(store().load().deleteAfterDays, 30)
        XCTAssertNil(store().load().lastEmptying)
    }
}
