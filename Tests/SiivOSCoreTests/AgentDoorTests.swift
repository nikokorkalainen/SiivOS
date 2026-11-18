import XCTest
@testable import SiivOSCore

final class AgentDoorTests: TemporaryDirectoryTestCase {
    private let moment = Date(timeIntervalSince1970: 1_800_000_000)

    private func makeDoor(isOn: Bool = true) throws -> AgentDoor {
        if isOn {
            try AgentDoorSwitch(dataDirectory: baseDirectory).set(true)
        }
        let home = self.home
        let moment = self.moment
        let sources = AgentDoor.Sources(
            snapshot: {
                SystemSnapshot(
                    osVersion: "Version 15.0",
                    processorCount: 8,
                    physicalMemoryBytes: 16_000_000_000,
                    uptimeSeconds: 7_200,
                    diskTotalBytes: 500_000_000_000,
                    diskAvailableBytes: 125_000_000_000
                )
            },
            scan: {
                // Pretend one app is open, so that its cache is held back.
                ScanEngine.clutter(
                    homeDirectory: home,
                    runningApps: [RunningApp(name: "Browser", bundleIdentifier: "com.example.Browser")]
                ).run()
            },
            protection: {
                ProtectionReport(sections: [
                    ProtectionSection(id: "macos", title: "Protection built into macOS", summary: "", findings: [
                        ProtectionFinding(id: "gatekeeper", level: .fine, title: "Gatekeeper", explanation: "On."),
                        ProtectionFinding(id: "filevault", level: .note, title: "FileVault", explanation: "Off.")
                    ]),
                    ProtectionSection(id: "background-items", title: "Background items", summary: "", findings: [
                        ProtectionFinding(id: "/a.plist", level: .attention, title: "com.odd.agent", explanation: "Runs from a temporary folder.", detail: "/tmp/odd")
                    ]),
                    ProtectionSection(id: "permissions", title: "Permissions", summary: "", findings: [], unavailableReason: "Needs Full Disk Access.")
                ])
            },
            performance: {
                func sample(_ cpu: Double?) -> PerformanceSample {
                    PerformanceSample(
                        date: moment, cpuUsedFraction: cpu, coreCount: 8,
                        memory: MemoryUsage(totalBytes: 16_000_000_000, usedBytes: 9_000_000_000, compressedBytes: 0, swapUsedBytes: 0, pressure: .normal),
                        topByCPU: [ProcessUsage(name: "mds_stores", cpuPercent: 160, memoryBytes: 300_000_000)],
                        topByMemory: [ProcessUsage(name: "Safari", cpuPercent: 4, memoryBytes: 2_000_000_000)],
                        battery: BatteryStatus(chargePercent: 80, isCharging: false, isPluggedIn: false, minutesRemaining: 300, cycleCount: 120, healthPercent: 92),
                        thermal: .normal, isLowPowerMode: false,
                        diskTotalBytes: 500_000_000_000, diskAvailableBytes: 125_000_000_000, uptimeSeconds: 7_200
                    )
                }
                return [sample(nil), sample(0.37)]
            },
            apps: {
                [
                    AppInfo(app: InstalledApp(url: URL(fileURLWithPath: "/Applications/Small.app"), name: "Small", bundleIdentifier: "com.example.Small", version: "1.0"), sizeBytes: 10_000_000, lastUsed: nil, isPartOfMacOS: false),
                    AppInfo(app: InstalledApp(url: URL(fileURLWithPath: "/Applications/Big.app"), name: "Big", bundleIdentifier: "com.example.Big", version: "2.1"), sizeBytes: 900_000_000, lastUsed: moment, isPartOfMacOS: false)
                ]
            }
        )
        return AgentDoor(dataDirectory: baseDirectory, sources: sources, now: { moment })
    }

    /// Reads an answer as the dictionary an agent would get.
    private func object(_ reply: AgentDoor.Reply, file: StaticString = #filePath, line: UInt = #line) throws -> [String: Any] {
        XCTAssertEqual(reply.exitCode, 0, reply.output, file: file, line: line)
        let parsed = try JSONSerialization.jsonObject(with: Data(reply.output.utf8))
        return try XCTUnwrap(parsed as? [String: Any], file: file, line: line)
    }

    // MARK: - The switch

    func testTheDoorIsOffUntilItIsTurnedOn() throws {
        let doorSwitch = AgentDoorSwitch(dataDirectory: baseDirectory)
        XCTAssertFalse(doorSwitch.isOn, "Off when nothing has been chosen")

        try doorSwitch.set(true)
        XCTAssertTrue(AgentDoorSwitch(dataDirectory: baseDirectory).isOn)

        try doorSwitch.set(false)
        XCTAssertFalse(AgentDoorSwitch(dataDirectory: baseDirectory).isOn)

        try Data("not json".utf8).write(to: doorSwitch.fileURL)
        XCTAssertFalse(doorSwitch.isOn, "A damaged file means off, never on")
    }

    func testAClosedDoorAnswersNothingAboutTheMac() throws {
        let door = try makeDoor(isOn: false)
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)

        for command in ["overview", "health", "changes", "cleanup", "performance", "protection", "apps", "history"] {
            let reply = door.answer([command])
            XCTAssertEqual(reply.exitCode, 2, command)
            XCTAssertTrue(reply.output.contains("The agent door is off"), command)
            XCTAssertFalse(reply.output.contains("com.example.Browser"), command)
        }

        let status = try object(door.answer(["status"]))
        XCTAssertEqual(status["door"] as? String, "off")
        XCTAssertEqual(door.answer(["help"]).exitCode, 0)
    }

    // MARK: - Help and mistakes

    func testHelpListsEveryQuestion() throws {
        let door = try makeDoor()
        let help = door.answer([])
        XCTAssertEqual(help, door.answer(["help"]))
        for command in AgentDoor.Command.allCases {
            XCTAssertTrue(help.output.contains(command.rawValue), command.rawValue)
        }
        XCTAssertTrue(help.output.contains("only reads"))

        let mistake = door.answer(["delete-everything"])
        XCTAssertEqual(mistake.exitCode, 64)
        XCTAssertTrue(mistake.output.contains("delete-everything"))
    }

    func testOptionsAreReadAsNameAndNumber() {
        XCTAssertEqual(AgentDoor.options(in: ["--limit", "5", "--days", "7"]), ["limit": 5, "days": 7])
        XCTAssertEqual(AgentDoor.options(in: ["--limit", "many", "stray", "--days"]), [:])
    }

    // MARK: - Answers

    func testStatusSaysWhereThingsAre() throws {
        let status = try object(try makeDoor().answer(["status"]))
        XCTAssertEqual(status["door"] as? String, "on")
        XCTAssertEqual(status["version"] as? String, AgentDoor.version)
        XCTAssertEqual(status["dataFolder"] as? String, baseDirectory.path)
        XCTAssertEqual((status["commands"] as? [String])?.count, AgentDoor.Command.allCases.count)
    }

    func testOverviewGivesDiskHealthAndTheHoldingArea() throws {
        let door = try makeDoor()
        let core = try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
        let file = try makeFile("Documents/old.bin", bytes: 500_000)
        _ = try core.apply(core.plan(removing: [file], reason: "Test."))
        _ = try HealthStore(fileURL: baseDirectory.appendingPathComponent("health-history.json")).record(
            HealthObservation(
                inventory: HealthInventory(apps: [], backgroundItems: [], extensions: [], profiles: [], protectionsOff: []),
                diskTotalBytes: 500_000_000_000, diskAvailableBytes: 125_000_000_000,
                memoryPressure: .normal, batteryHealthPercent: nil, attentionCount: 0
            ),
            now: moment
        )

        let overview = try object(door.answer(["overview"]))

        let disk = try XCTUnwrap(overview["disk"] as? [String: Any])
        XCTAssertEqual(disk["freePercent"] as? Int, 25)
        XCTAssertEqual(disk["availableBytes"] as? Int, 125_000_000_000)
        XCTAssertEqual((overview["health"] as? [String: Any])?["score"] as? Int, 100)
        XCTAssertGreaterThanOrEqual(overview["holdingAreaBytes"] as? Int ?? 0, 500_000)
        XCTAssertEqual(overview["hoursSinceRestart"] as? Double, 2)
    }

    func testHealthExplainsEveryPointOfTheScore() throws {
        let health = try object(try makeDoor().answer(["health"]))

        // FileVault is off (5 of 25) and one thing needs a closer look (5 of 10).
        XCTAssertEqual(health["score"] as? Int, 90)
        let parts = try XCTUnwrap(health["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.map { $0["id"] as? String }, ["disk", "memory", "protection", "closer-look", "battery"])
        XCTAssertTrue(parts.allSatisfy { !(($0["explanation"] as? String) ?? "").isEmpty })
        XCTAssertEqual((health["recentReadings"] as? [Any])?.count, 0, "Asking does not add a reading")
    }

    func testChangesAreNewestFirstAndLimitedToTheDaysAskedFor() throws {
        let door = try makeDoor()
        let store = HealthStore(fileURL: baseDirectory.appendingPathComponent("health-history.json"))
        func observation(_ items: [HealthInventory.Entry]) -> HealthObservation {
            HealthObservation(
                inventory: HealthInventory(apps: [], backgroundItems: items, extensions: [], profiles: [], protectionsOff: []),
                diskTotalBytes: 500, diskAvailableBytes: 100, memoryPressure: .normal, batteryHealthPercent: nil, attentionCount: 0
            )
        }
        _ = try store.record(observation([]), now: moment.addingTimeInterval(-40 * 86_400))
        _ = try store.record(observation([HealthInventory.Entry(key: "/a.plist", name: "com.new.agent")]), now: moment.addingTimeInterval(-2 * 86_400))

        let month = try object(door.answer(["changes"]))
        let changes = try XCTUnwrap(month["changes"] as? [[String: Any]])
        XCTAssertEqual(changes.map { $0["kind"] as? String }, ["backgroundItemAdded"])
        XCTAssertEqual(changes.first?["title"] as? String, "New background item: com.new.agent")
        XCTAssertEqual(changes.first?["worthALook"] as? Bool, true)

        let all = try object(door.answer(["changes", "--days", "60"]))
        XCTAssertEqual((all["changes"] as? [[String: Any]])?.map { $0["kind"] as? String }, ["backgroundItemAdded", "trackingStarted"])
        let today = try object(door.answer(["changes", "--days", "1"]))
        XCTAssertEqual((today["changes"] as? [Any])?.count, 0)
    }

    func testCleanupListsItemsWithTheirLabelsAndReasons() throws {
        // Caches under 1 MB are not listed. Sizes on disk are rounded up, and by different
        // amounts on a Mac and on Linux, so both of these are well above that on either.
        try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 3_000_000)
        try makeFile("Library/Caches/com.example.Editor/data.bin", bytes: 6_000_000)
        let door = try makeDoor()

        let everything = try object(door.answer(["cleanup"]))
        let allItems = try XCTUnwrap((everything["groups"] as? [[String: Any]])?.first?["items"] as? [[String: Any]])
        XCTAssertEqual(allItems.count, 2)
        XCTAssertNil(allItems[0]["heldBack"], "The editor is not open")
        XCTAssertTrue((allItems[1]["heldBack"] as? String)?.contains("Browser is open") ?? false)
        XCTAssertEqual(
            everything["safeToRemoveBytes"] as? Int,
            allItems[0]["sizeBytes"] as? Int,
            "Only the editor's cache counts as safe to remove; the open app's cache does not"
        )

        let cleanup = try object(door.answer(["cleanup", "--limit", "1"]))

        let groups = try XCTUnwrap(cleanup["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.map { $0["id"] as? String }, ["caches", "logs", "leftovers", "old-downloads", "large-files", "duplicates"])
        let caches = try XCTUnwrap(groups.first)
        XCTAssertEqual(caches["itemCount"] as? Int, 2)
        let items = try XCTUnwrap(caches["items"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1, "Only as many as asked for, largest first")
        XCTAssertTrue((items[0]["path"] as? String)?.hasSuffix("com.example.Editor") ?? false)
        XCTAssertEqual(items[0]["label"] as? String, "safeToRemove")
        XCTAssertFalse((items[0]["labelReason"] as? String ?? "").isEmpty)
        XCTAssertTrue((cleanup["note"] as? String)?.contains("only reads") ?? false)
    }

    func testPerformanceGivesFiguresAndWhatSiivOSMakesOfThem() throws {
        let performance = try object(try makeDoor().answer(["performance"]))

        XCTAssertEqual(performance["processorPercent"] as? Int, 37)
        XCTAssertEqual((performance["memory"] as? [String: Any])?["pressure"] as? String, "normal")
        XCTAssertEqual((performance["battery"] as? [String: Any])?["healthPercent"] as? Int, 92)
        let busiest = try XCTUnwrap((performance["busiestPrograms"] as? [[String: Any]])?.first)
        XCTAssertEqual(busiest["name"] as? String, "mds_stores")
        XCTAssertEqual(busiest["processorPercent"] as? Double, 20, "Share of all eight cores")
        XCTAssertTrue((busiest["whatItIs"] as? String)?.contains("Spotlight") ?? false)
        XCTAssertNotNil(performance["findings"] as? [[String: Any]])
    }

    func testProtectionListsWhatWasFoundAndWhatCouldNotBeRead() throws {
        let protection = try object(try makeDoor().answer(["protection"]))

        XCTAssertEqual(protection["overall"] as? String, "attention")
        XCTAssertEqual(protection["needingACloserLook"] as? Int, 1)
        let groups = try XCTUnwrap(protection["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.count, 3)
        let odd = try XCTUnwrap((groups[1]["findings"] as? [[String: Any]])?.first)
        XCTAssertEqual(odd["level"] as? String, "attention")
        XCTAssertEqual(odd["detail"] as? String, "/tmp/odd")
        XCTAssertEqual(groups[2]["unavailable"] as? String, "Needs Full Disk Access.")
    }

    func testAppsAreLargestFirst() throws {
        let door = try makeDoor()
        let apps = try object(door.answer(["apps"]))
        XCTAssertEqual(apps["appCount"] as? Int, 2)
        XCTAssertEqual(apps["totalBytes"] as? Int, 910_000_000)
        XCTAssertEqual((apps["apps"] as? [[String: Any]])?.map { $0["name"] as? String }, ["Big", "Small"])

        let one = try object(door.answer(["apps", "--limit", "1"]))
        XCTAssertEqual((one["apps"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual(one["appCount"] as? Int, 2)
    }

    func testHistoryShowsWhatSiivOSChangedAndWhatCanBePutBack() throws {
        let door = try makeDoor()
        let core = try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
        let file = try makeFile("Documents/old.bin", bytes: 500_000)
        let result = try core.apply(core.plan(removing: [file], title: "Removed old.bin", reason: "Test."))

        let history = try object(door.answer(["history"]))
        let change = try XCTUnwrap((history["changes"] as? [[String: Any]])?.first)
        XCTAssertEqual(change["title"] as? String, "Removed old.bin")
        XCTAssertEqual(change["canBePutBack"] as? Bool, true)
        XCTAssertEqual(((change["items"] as? [[String: Any]])?.first)?["state"] as? String, "held")

        _ = try core.undo(recordID: result.record.id)
        let after = try object(door.answer(["history"]))
        XCTAssertEqual(((after["changes"] as? [[String: Any]])?.first)?["canBePutBack"] as? Bool, false)
        XCTAssertEqual(after["holdingAreaBytes"] as? Int, 0)
    }

    func testTheRealChecksSayWhatTheyAreLookingAt() {
        final class Lines: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: [String] = []
            func add(_ line: String) {
                lock.lock()
                stored.append(line)
                lock.unlock()
            }
            var all: [String] {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
        }
        let lines = Lines()
        let sources = AgentDoor.Sources.live(homeDirectory: home) { lines.add($0) }

        _ = sources.scan()

        XCTAssertEqual(lines.all.count, 6, "One line for each of the six checks")
        XCTAssertEqual(lines.all.first, "Checking: App caches…")
    }

    // MARK: - Only reading

    func testAnsweringNeverCreatesChangesOrRemovesAnything() throws {
        let door = try makeDoor()
        let cache = try makeFile("Library/Caches/com.example.Browser/data.bin", bytes: 500_000)
        try makeFile("Downloads/installer.dmg", bytes: 100)

        func everything() throws -> [String] {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            var paths: [String] = []
            while let url = enumerator?.nextObject() as? URL {
                paths.append(url.path)
            }
            return paths.sorted()
        }
        let before = try everything()

        for command in AgentDoor.Command.allCases {
            _ = door.answer([command.rawValue])
        }

        XCTAssertEqual(try everything(), before, "No file appeared or disappeared, in SiivOS's folder or the home folder")
        XCTAssertTrue(exists(cache))
    }
}
