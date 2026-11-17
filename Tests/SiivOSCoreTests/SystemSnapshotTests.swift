import XCTest
@testable import SiivOSCore

final class SystemSnapshotTests: XCTestCase {
    private func snapshot(total: Int64?, available: Int64?) -> SystemSnapshot {
        SystemSnapshot(
            osVersion: "Test",
            processorCount: 8,
            physicalMemoryBytes: 16_000_000_000,
            uptimeSeconds: 3_600,
            diskTotalBytes: total,
            diskAvailableBytes: available
        )
    }

    func testDiskUsageIsCalculatedFromTotalAndAvailable() {
        let result = snapshot(total: 1_000, available: 250)
        XCTAssertEqual(result.diskUsedBytes, 750)
        XCTAssertEqual(result.diskUsedFraction ?? -1, 0.75, accuracy: 0.0001)
    }

    func testDiskUsageIsUnknownWhenDiskCouldNotBeRead() {
        let result = snapshot(total: nil, available: nil)
        XCTAssertNil(result.diskUsedBytes)
        XCTAssertNil(result.diskUsedFraction)
    }

    func testDiskUsageNeverGoesBelowZeroOrAboveFull() {
        let moreAvailableThanTotal = snapshot(total: 1_000, available: 5_000)
        XCTAssertEqual(moreAvailableThanTotal.diskUsedBytes, 0)
        XCTAssertEqual(moreAvailableThanTotal.diskUsedFraction ?? -1, 0, accuracy: 0.0001)

        let emptyDisk = snapshot(total: 0, available: 0)
        XCTAssertNil(emptyDisk.diskUsedFraction)
    }

    func testCurrentSnapshotReadsThisMac() {
        let result = SystemSnapshot.current()
        XCTAssertFalse(result.osVersion.isEmpty)
        XCTAssertGreaterThan(result.processorCount, 0)
        XCTAssertGreaterThan(result.physicalMemoryBytes, 0)
        XCTAssertNotNil(result.diskTotalBytes)
    }
}
