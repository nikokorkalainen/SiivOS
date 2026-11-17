import XCTest
@testable import SiivOSCore

private struct FakeScanner: SystemScanner {
    let id: String
    let title: String
    let summary = "A scanner used only in tests."
    let sizes: [Int64]

    func scan() throws -> [Finding] {
        sizes.map { size in
            Finding(
                url: URL(fileURLWithPath: "/tmp/\(id)-\(size)"),
                sizeBytes: size,
                explanation: "A pretend finding."
            )
        }
    }
}

private struct BrokenScanner: SystemScanner {
    struct Failure: Error {}

    let id = "broken"
    let title = "Broken"
    let summary = "A scanner that always fails."

    func scan() throws -> [Finding] {
        throw Failure()
    }
}

final class ScanEngineTests: XCTestCase {
    func testReportCollectsFindingsFromEveryScannerLargestFirst() {
        let engine = ScanEngine(scanners: [
            FakeScanner(id: "caches", title: "Caches", sizes: [10, 300, 20]),
            FakeScanner(id: "logs", title: "Logs", sizes: [5])
        ])

        let report = engine.run()

        XCTAssertEqual(report.sections.map { $0.id }, ["caches", "logs"])
        XCTAssertEqual(report.sections[0].findings.map { $0.sizeBytes }, [300, 20, 10])
        XCTAssertEqual(report.sections[0].totalBytes, 330)
        XCTAssertEqual(report.totalBytes, 335)
        XCTAssertEqual(report.findingCount, 4)
        XCTAssertNil(report.sections[0].failure)
    }

    func testOneFailingScannerDoesNotStopTheOthers() {
        let engine = ScanEngine(scanners: [
            BrokenScanner(),
            FakeScanner(id: "logs", title: "Logs", sizes: [5])
        ])

        let report = engine.run()

        XCTAssertNotNil(report.sections[0].failure)
        XCTAssertTrue(report.sections[0].findings.isEmpty)
        XCTAssertEqual(report.sections[1].findings.count, 1)
        XCTAssertEqual(report.findingCount, 1)
    }

    func testAnEngineWithNoScannersFindsNothing() {
        let report = ScanEngine(scanners: []).run()
        XCTAssertTrue(report.sections.isEmpty)
        XCTAssertEqual(report.totalBytes, 0)
    }
}
