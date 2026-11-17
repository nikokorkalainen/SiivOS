import XCTest
@testable import SiivOSCore

final class ActionLogTests: TemporaryDirectoryTestCase {
    private var log: ActionLog {
        ActionLog(fileURL: baseDirectory.appendingPathComponent("action-log.json"))
    }

    private func record(title: String) -> ActionRecord {
        ActionRecord(
            id: UUID(),
            date: Date(timeIntervalSince1970: 1_800_000_000),
            title: title,
            explanation: "Explained before it ran.",
            items: [
                ActionRecord.Item(
                    held: HeldItem(id: UUID(), originalPath: "/Users/test/a.txt", sizeBytes: 100),
                    state: .held
                ),
                ActionRecord.Item(
                    held: HeldItem(id: UUID(), originalPath: "/Users/test/b.txt", sizeBytes: 40),
                    state: .restored
                )
            ]
        )
    }

    func testAMissingLogMeansNothingHasHappened() throws {
        XCTAssertEqual(try log.load(), [])
    }

    func testRecordsAreReadBackExactlyAsSaved() throws {
        let records = [record(title: "First"), record(title: "Second")]
        try log.save(records)
        XCTAssertEqual(try log.load(), records)
    }

    func testADamagedLogIsAnErrorNotAnEmptyHistory() throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try Data("this is not json".utf8).write(to: log.fileURL)
        XCTAssertThrowsError(try log.load())
    }

    func testRecordTotalsFollowItemStates() {
        let example = record(title: "Totals")
        XCTAssertEqual(example.totalBytes, 140)
        XCTAssertEqual(example.heldBytes, 100)
        XCTAssertTrue(example.canUndo)
        XCTAssertEqual(example.count(of: .held), 1)
        XCTAssertEqual(example.count(of: .restored), 1)
        XCTAssertEqual(example.count(of: .deleted), 0)
    }
}
