import XCTest
@testable import SiivOSCore

final class ClamAVTests: TemporaryDirectoryTestCase {
    private var programs: URL {
        root.appendingPathComponent("bin", isDirectory: true)
    }

    private var definitions: URL {
        baseDirectory.appendingPathComponent("ClamAV", isDirectory: true)
    }

    /// Puts a pretend ClamAV program, written as a shell script, where SiivOS will look.
    private func install(_ name: String, script: String) throws {
        try FileManager.default.createDirectory(at: programs, withIntermediateDirectories: true)
        let file = programs.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
    }

    private func makeClamAV() -> ClamAV {
        ClamAV(dataDirectory: definitions, searchDirectories: [programs.path])
    }

    // MARK: - Reading ClamAV's output

    func testVersionLineIsReadWithAndWithoutDefinitions() {
        let full = ClamAV.parseVersion("ClamAV 1.4.1/27450/Tue Nov 17 09:35:12 2026\n")
        XCTAssertEqual(full.engine, "1.4.1")
        XCTAssertEqual(full.definitions, "27450")
        XCTAssertNotNil(full.definitionsDate)

        // Single-digit days are padded with an extra space.
        XCTAssertNotNil(ClamAV.parseVersion("ClamAV 1.4.1/27300/Mon Nov  2 08:00:00 2026").definitionsDate)

        let bare = ClamAV.parseVersion("ClamAV 1.4.1\n")
        XCTAssertEqual(bare.engine, "1.4.1")
        XCTAssertNil(bare.definitions)
        XCTAssertNil(bare.definitionsDate)

        XCTAssertNil(ClamAV.parseVersion("command not found").engine)
    }

    func testScanOutputIsReadIntoDetectionsAndACount() {
        let output = """
        /Users/test/Downloads/eicar.txt: Eicar-Signature FOUND
        /Users/test/Downloads/odd: name.zip: Win.Trojan.Example-123 FOUND

        ----------- SCAN SUMMARY -----------
        Known viruses: 8700000
        Engine version: 1.4.1
        Scanned directories: 3
        Scanned files: 142
        Infected files: 2
        """
        let parsed = ClamAV.parseScan(output)

        XCTAssertEqual(parsed.scannedFiles, 142)
        XCTAssertEqual(parsed.detections, [
            MalwareDetection(path: "/Users/test/Downloads/eicar.txt", name: "Eicar-Signature"),
            MalwareDetection(path: "/Users/test/Downloads/odd: name.zip", name: "Win.Trojan.Example-123")
        ])
        XCTAssertTrue(ClamAV.parseScan("Scanned files: 0\n").detections.isEmpty)
    }

    // MARK: - With a pretend ClamAV installed

    func testDetectionsWhoseFilesAreGoneDropOffTheList() throws {
        let stillThere = try makeFile("Downloads/bad.dmg")
        let removed = home.appendingPathComponent("Downloads/gone.dmg")
        let result = MalwareScanResult(
            scannedFiles: 12,
            detections: [
                MalwareDetection(path: stillThere.path, name: "Osx.Test.One"),
                MalwareDetection(path: removed.path, name: "Osx.Test.Two")
            ],
            problem: nil,
            wasCancelled: false
        )

        let updated = result.removingDetectionsNoLongerOnDisk()

        XCTAssertEqual(updated.detections.map { $0.name }, ["Osx.Test.One"])
        XCTAssertEqual(updated.detections.first?.url, stillThere)
        XCTAssertEqual(updated.scannedFiles, 12)
    }

    func testClamAVThatIsNotInstalledIsReportedAsSuch() {
        let clamAV = makeClamAV()
        XCTAssertNil(clamAV.status())
        XCTAssertNotNil(clamAV.scan([home]).problem)
        XCTAssertNotNil(clamAV.updateDefinitions())
    }

    func testStatusSaysWhetherDefinitionsAreThere() throws {
        try install("clamscan", script: "echo 'ClamAV 1.4.1'")
        let withoutUpdater = try XCTUnwrap(makeClamAV().status())
        XCTAssertEqual(withoutUpdater.engineVersion, "1.4.1")
        XCTAssertFalse(withoutUpdater.hasDefinitions)
        XCTAssertNil(withoutUpdater.updaterPath)

        try install("clamscan", script: "echo 'ClamAV 1.4.1/27450/Tue Nov 17 09:35:12 2026'")
        try install("freshclam", script: "exit 0")
        let complete = try XCTUnwrap(makeClamAV().status())
        XCTAssertTrue(complete.hasDefinitions)
        XCTAssertEqual(complete.definitionsVersion, "27450")
        XCTAssertNotNil(complete.updaterPath)
    }

    func testUpdatingDefinitionsWritesItsOwnSettingsAndUsesItsOwnFolder() throws {
        try install("clamscan", script: "echo 'ClamAV 1.4.1'")
        // The pretend updater records how it was called and leaves a definitions file.
        try install("freshclam", script: """
        for argument in "$@"; do
            case "$argument" in
                --datadir=*) folder="${argument#--datadir=}" ;;
            esac
        done
        echo "$@" > "$folder/called-with.txt"
        touch "$folder/daily.cvd"
        """)
        let clamAV = makeClamAV()

        XCTAssertNil(clamAV.updateDefinitions())

        let settings = try String(contentsOf: definitions.appendingPathComponent("freshclam.conf"), encoding: .utf8)
        XCTAssertTrue(settings.contains("DatabaseMirror database.clamav.net"))
        let call = try String(contentsOf: definitions.appendingPathComponent("called-with.txt"), encoding: .utf8)
        XCTAssertTrue(call.contains("--config-file=\(definitions.path)/freshclam.conf"))
        XCTAssertTrue(call.contains("--datadir=\(definitions.path)"))
        // The file the updater left counts as definitions, even though the version line is bare.
        XCTAssertEqual(clamAV.status()?.hasDefinitions, true)
    }

    func testAFailedDownloadIsExplained() throws {
        try install("clamscan", script: "echo 'ClamAV 1.4.1'")
        try install("freshclam", script: "echo 'Connecting'\necho 'ERROR: Could not reach the server'\nexit 1")

        let problem = try XCTUnwrap(makeClamAV().updateDefinitions())
        XCTAssertTrue(problem.contains("Could not reach the server"))
    }

    func testAScanReportsWhatItFoundAndWhereItLooked() throws {
        let folder = try makeFolder("Downloads")
        try install("clamscan", script: """
        for argument in "$@"; do last="$argument"; done
        echo "$@" > "\(root.path)/scan-called-with.txt"
        echo "$last/eicar.txt: Eicar-Signature FOUND"
        echo "----------- SCAN SUMMARY -----------"
        echo "Scanned files: 7"
        echo "Infected files: 1"
        exit 1
        """)

        let result = makeClamAV().scan([folder])

        XCTAssertNil(result.problem)
        XCTAssertFalse(result.wasCancelled)
        XCTAssertEqual(result.scannedFiles, 7)
        XCTAssertEqual(result.detections.map { $0.name }, ["Eicar-Signature"])
        XCTAssertTrue(result.detections[0].path.hasSuffix("Downloads/eicar.txt"))

        let call = try String(contentsOf: root.appendingPathComponent("scan-called-with.txt"), encoding: .utf8)
        XCTAssertTrue(call.contains("--database=\(definitions.path)"))
        XCTAssertTrue(call.contains("--recursive"))
        XCTAssertTrue(call.contains("--infected"))
    }

    func testACleanScanAndAFailedScanAreToldApart() throws {
        try install("clamscan", script: "echo 'Scanned files: 3'\nexit 0")
        let clean = makeClamAV().scan([home])
        XCTAssertNil(clean.problem)
        XCTAssertTrue(clean.detections.isEmpty)
        XCTAssertEqual(clean.scannedFiles, 3)

        try install("clamscan", script: "echo 'LibClamAV Error: No supported database files found'\nexit 2")
        let failed = makeClamAV().scan([home])
        XCTAssertTrue(failed.problem?.contains("No supported database files found") ?? false)
    }

    func testAScanCanBeStopped() throws {
        try install("clamscan", script: "exec sleep 30")
        let clamAV = makeClamAV()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            clamAV.cancel()
        }

        let started = Date()
        let result = clamAV.scan([home])

        XCTAssertTrue(result.wasCancelled)
        XCTAssertNil(result.problem)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }
}
