import XCTest
@testable import SiivOSCore

final class HealthTests: TemporaryDirectoryTestCase {
    private typealias Entry = HealthInventory.Entry

    private func inventory(
        apps: [Entry] = [Entry(key: "com.example.Notes", name: "Notes", detail: "1.0")],
        backgroundItems: [Entry] = [],
        extensions: [Entry] = [],
        profiles: [Entry] = [],
        protectionsOff: [String] = []
    ) -> HealthInventory {
        HealthInventory(apps: apps, backgroundItems: backgroundItems, extensions: extensions, profiles: profiles, protectionsOff: protectionsOff)
    }

    private func observation(
        _ inventory: HealthInventory? = nil,
        available: Int64? = 250_000_000_000,
        total: Int64? = 500_000_000_000,
        pressure: MemoryUsage.Pressure? = .normal,
        battery: Int? = nil,
        attention: Int = 0
    ) -> HealthObservation {
        HealthObservation(
            inventory: inventory ?? self.inventory(),
            diskTotalBytes: total,
            diskAvailableBytes: available,
            memoryPressure: pressure,
            batteryHealthPercent: battery,
            attentionCount: attention
        )
    }

    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func hours(_ count: Double) -> Date { start.addingTimeInterval(count * 3_600) }

    // MARK: - The score

    func testAHealthyMacScoresAHundredAndSaysWhy() {
        let score = observation(battery: 95).score
        XCTAssertEqual(score.total, 100)
        XCTAssertEqual(score.parts.map { $0.id }, ["disk", "memory", "protection", "closer-look", "battery"])
        XCTAssertTrue(score.parts.allSatisfy { !$0.explanation.isEmpty && $0.points == $0.maximum })
    }

    func testAMacWithoutABatteryIsNotMarkedDownForIt() {
        let score = observation(battery: nil).score
        XCTAssertEqual(score.total, 100)
        XCTAssertFalse(score.parts.contains { $0.id == "battery" })
    }

    func testFreeDiskSpaceWeighsMost() {
        func diskPoints(_ available: Int64) -> Int {
            observation(available: available).score.parts.first { $0.id == "disk" }?.points ?? -1
        }
        XCTAssertEqual(diskPoints(100_000_000_000), 40, "A fifth free is full marks")
        XCTAssertEqual(diskPoints(62_500_000_000), 20, "Halfway between 5 % and 20 % free")
        XCTAssertEqual(diskPoints(25_000_000_000), 0)
        XCTAssertEqual(diskPoints(5_000_000_000), 0)
        XCTAssertEqual(observation(available: 5_000_000_000).score.total, 56, "56 of the other 90 points, scaled")
    }

    func testProtectionsThatAreOffCostPointsExceptTheFirewall() {
        func protectionPoints(_ off: [String]) -> Int {
            observation(inventory(protectionsOff: off)).score.parts.first { $0.id == "protection" }?.points ?? -1
        }
        XCTAssertEqual(protectionPoints([]), 25)
        XCTAssertEqual(protectionPoints(["firewall"]), 25, "Off is the macOS default, so it costs nothing")
        XCTAssertEqual(protectionPoints(["filevault"]), 20)
        XCTAssertEqual(protectionPoints(["gatekeeper", "system-integrity-protection", "filevault"]), 0)

        let part = observation(inventory(protectionsOff: ["filevault", "firewall"])).score.parts.first { $0.id == "protection" }
        XCTAssertTrue(part?.explanation.contains("FileVault") ?? false)
        XCTAssertFalse(part?.explanation.contains("Firewall") ?? true)
    }

    func testMemoryThingsNeedingALookAndAnAgedBatteryCostPoints() {
        func points(_ id: String, _ observation: HealthObservation) -> Int {
            observation.score.parts.first { $0.id == id }?.points ?? -1
        }
        XCTAssertEqual(points("memory", observation(pressure: .elevated)), 8)
        XCTAssertEqual(points("memory", observation(pressure: .high)), 0)
        XCTAssertEqual(points("closer-look", observation(attention: 1)), 5)
        XCTAssertEqual(points("closer-look", observation(attention: 7)), 0)
        XCTAssertEqual(points("battery", observation(battery: 80)), 10)
        XCTAssertEqual(points("battery", observation(battery: 70)), 5)
        XCTAssertEqual(points("battery", observation(battery: 40)), 0)
    }

    // MARK: - Recording

    func testTheFirstReadingStartsTheHistory() {
        let history = HealthTimeline.record(observation(), into: HealthHistory(), now: start)

        XCTAssertEqual(history.readings.count, 1)
        XCTAssertEqual(history.readings[0].score, 100)
        XCTAssertEqual(history.readings[0].diskAvailableBytes, 250_000_000_000)
        XCTAssertEqual(history.events.map { $0.kind }, [.trackingStarted])
        XCTAssertEqual(history.inventory, inventory())
    }

    func testAppsAddedRemovedAndUpdatedBecomeEvents() {
        let first = HealthTimeline.record(observation(), into: HealthHistory(), now: start)
        let changed = inventory(apps: [
            Entry(key: "com.example.Notes", name: "Notes", detail: "1.1"),
            Entry(key: "com.example.Paint", name: "Paint", detail: "3.0")
        ])
        let second = HealthTimeline.record(observation(changed), into: first, now: hours(5))
        let third = HealthTimeline.record(observation(inventory(apps: [Entry(key: "com.example.Paint", name: "Paint", detail: "3.0")])), into: second, now: hours(10))

        let afterSecond = second.events.dropFirst()
        XCTAssertEqual(afterSecond.map { $0.kind }, [.appUpdated, .appAdded])
        XCTAssertEqual(afterSecond.first?.detail, "1.0 → 1.1")
        XCTAssertEqual(afterSecond.first?.title, "Notes was updated")
        XCTAssertEqual(third.events.last?.kind, .appRemoved)
        XCTAssertEqual(third.events.last?.title, "Notes was removed")
        XCTAssertEqual(third.readings.count, 3)
    }

    func testANewBackgroundItemIsNoteworthy() {
        let first = HealthTimeline.record(observation(), into: HealthHistory(), now: start)
        let withAgent = inventory(backgroundItems: [Entry(key: "/Users/x/Library/LaunchAgents/com.new.agent.plist", name: "com.new.agent")])
        let second = HealthTimeline.record(observation(withAgent), into: first, now: hours(8))

        let event = second.events.last
        XCTAssertEqual(event?.kind, .backgroundItemAdded)
        XCTAssertEqual(event?.isNoteworthy, true)
        XCTAssertEqual(event?.title, "New background item: com.new.agent")
        XCTAssertNotNil(event?.explanation)

        let third = HealthTimeline.record(observation(), into: second, now: hours(16))
        XCTAssertEqual(third.events.last?.kind, .backgroundItemRemoved)
        XCTAssertEqual(third.events.last?.isNoteworthy, false)
    }

    func testExtensionsProfilesAndProtectionsAreFollowedToo() {
        let first = HealthTimeline.record(observation(), into: HealthHistory(), now: start)
        let changed = inventory(
            extensions: [Entry(key: "Chrome|Default|abc", name: "Ad Blocker", detail: "Chrome")],
            profiles: [Entry(key: "profile:com.company.wifi", name: "Company Wi-Fi")],
            protectionsOff: ["filevault"]
        )
        let second = HealthTimeline.record(observation(changed), into: first, now: hours(7))

        XCTAssertEqual(second.events.dropFirst().map { $0.kind }, [.extensionAdded, .profileAdded, .protectionTurnedOff])
        XCTAssertEqual(second.events.last?.title, "FileVault was turned off")
        XCTAssertEqual(second.events.last?.isNoteworthy, true)
        XCTAssertEqual(second.readings.last?.score, 94, "FileVault being off costs five of the 90 points a Mac without a battery can get")

        let third = HealthTimeline.record(observation(), into: second, now: hours(14))
        XCTAssertEqual(Set(third.events.suffix(3).map { $0.kind }), [.extensionRemoved, .profileRemoved, .protectionTurnedOn])
    }

    func testOnlyBigChangesInFreeSpaceAreEvents() {
        let first = HealthTimeline.record(observation(available: 250_000_000_000), into: HealthHistory(), now: start)
        // Two percent of a 500 GB disk is 10 GB, which is more than the 5 GB floor.
        let smallDrop = HealthTimeline.record(observation(available: 245_000_000_000), into: first, now: hours(5))
        XCTAssertEqual(smallDrop.events.count, 1)

        let bigDrop = HealthTimeline.record(observation(available: 220_000_000_000), into: smallDrop, now: hours(10))
        XCTAssertEqual(bigDrop.events.last?.kind, .freeSpaceWentDown)
        XCTAssertEqual(bigDrop.events.last?.amountBytes, 25_000_000_000)

        let freed = HealthTimeline.record(observation(available: 260_000_000_000), into: bigDrop, now: hours(15))
        XCTAssertEqual(freed.events.last?.kind, .freeSpaceWentUp)
        XCTAssertEqual(freed.events.last?.amountBytes, 40_000_000_000)
        XCTAssertTrue(freed.events.last?.title.hasPrefix("Free space went up by") ?? false)
    }

    func testReadingsCloseTogetherDoNotFillTheHistoryOrHideSlowChanges() {
        var history = HealthTimeline.record(observation(available: 250_000_000_000), into: HealthHistory(), now: start)
        // Opened again several times within the hour, losing 4 GB each time.
        for step in 1...4 {
            history = HealthTimeline.record(
                observation(available: 250_000_000_000 - Int64(step) * 4_000_000_000),
                into: history,
                now: start.addingTimeInterval(Double(step) * 600)
            )
        }
        XCTAssertEqual(history.readings.count, 2, "The quiet readings fold into the first; the one with a change is kept")
        XCTAssertEqual(history.events.last?.kind, .freeSpaceWentDown, "12 GB since the first reading adds up to an event")
    }

    func testTheHistoryIsCappedInLength() {
        var history = HealthHistory()
        for index in 0..<(HealthTimeline.maximumReadings + 20) {
            history = HealthTimeline.record(observation(), into: history, now: hours(Double(index) * 2))
        }
        XCTAssertEqual(history.readings.count, HealthTimeline.maximumReadings)
        XCTAssertEqual(history.events.count, 1)
    }

    func testNoteworthyChangesCanBeAskedForSinceAMoment() {
        let history = HealthHistory(events: [
            HealthEvent(date: hours(0), kind: .trackingStarted),
            HealthEvent(date: hours(1), kind: .backgroundItemAdded, subject: "com.first.agent"),
            HealthEvent(date: hours(2), kind: .appAdded, subject: "Notes"),
            HealthEvent(date: hours(3), kind: .protectionTurnedOff, subject: "filevault"),
            HealthEvent(date: hours(4), kind: .profileAdded, subject: "Company Wi-Fi")
        ])

        XCTAssertEqual(history.noteworthyEvents(after: nil).map { $0.kind }, [.profileAdded, .protectionTurnedOff, .backgroundItemAdded], "Newest first")
        XCTAssertEqual(history.noteworthyEvents(after: hours(1)).map { $0.kind }, [.profileAdded, .protectionTurnedOff], "What was noticed at that moment has been seen")
        XCTAssertTrue(history.noteworthyEvents(after: hours(4)).isEmpty)
        XCTAssertTrue(HealthHistory().noteworthyEvents(after: nil).isEmpty)
    }

    func testChangesReadInFinnishWhenTheAppIsShownInFinnish() {
        L10n.overrideLanguage = .finnish
        defer { L10n.overrideLanguage = .english }

        let added = HealthEvent(date: start, kind: .backgroundItemAdded, subject: "com.new.agent")
        let turnedOff = HealthEvent(date: start, kind: .protectionTurnedOff, subject: "system-integrity-protection")

        XCTAssertEqual(added.title, "Uusi taustakohde: com.new.agent")
        XCTAssertEqual(turnedOff.title, "Järjestelmän eheyden suojaus poistettiin käytöstä")
        XCTAssertEqual(observation().score.parts.first?.title, "Levytila")
    }

    // MARK: - Storing

    func testTheStoreKeepsHistoryBetweenLaunches() throws {
        let file = baseDirectory.appendingPathComponent("health-history.json")
        XCTAssertEqual(HealthStore(fileURL: file).load(), HealthHistory())

        let recorded = try HealthStore(fileURL: file).record(observation(), now: start)
        let later = try HealthStore(fileURL: file).record(
            observation(inventory(apps: [])),
            now: hours(6)
        )

        XCTAssertEqual(recorded.readings.count, 1)
        XCTAssertEqual(later.readings.count, 2)
        XCTAssertEqual(later.events.map { $0.kind }, [.trackingStarted, .appRemoved])
        XCTAssertEqual(HealthStore(fileURL: file).load(), later)
    }

    func testADamagedHistoryFileStartsAfreshInsteadOfFailing() throws {
        let file = baseDirectory.appendingPathComponent("health-history.json")
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: file)

        XCTAssertEqual(HealthStore(fileURL: file).load(), HealthHistory())
        XCTAssertEqual(try HealthStore(fileURL: file).record(observation(), now: start).readings.count, 1)
    }

    // MARK: - From the checks SiivOS already has

    func testAnObservationIsBuiltFromTheProtectionCheckAndAReading() {
        let report = ProtectionReport(sections: [
            ProtectionSection(id: "macos", title: "", summary: "", findings: [
                ProtectionFinding(id: "gatekeeper", level: .fine, title: "Gatekeeper", explanation: ""),
                ProtectionFinding(id: "filevault", level: .note, title: "FileVault", explanation: ""),
                ProtectionFinding(id: "system-integrity-protection", level: .attention, title: "SIP", explanation: "")
            ]),
            ProtectionSection(id: "background-items", title: "", summary: "", findings: [
                ProtectionFinding(id: "/a.plist", level: .attention, title: "com.odd.agent", explanation: "", detail: "/tmp/odd"),
                ProtectionFinding(id: "/b.plist", level: .fine, title: "com.fine.agent", explanation: "")
            ]),
            ProtectionSection(id: "browser-extensions", title: "", summary: "", findings: [
                ProtectionFinding(id: "Chrome|Default|abc", level: .note, title: "Ad Blocker", explanation: "", detail: "Chrome")
            ]),
            ProtectionSection(id: "profiles", title: "", summary: "", findings: [])
        ])
        let apps = [
            InstalledApp(url: URL(fileURLWithPath: "/Applications/Notes.app"), name: "Notes", bundleIdentifier: "com.example.Notes", version: "2.0"),
            InstalledApp(url: URL(fileURLWithPath: "/Applications/Tool.app"), name: "Tool", bundleIdentifier: nil, version: nil)
        ]
        let sample = PerformanceSample(
            date: start, cpuUsedFraction: nil, coreCount: 8,
            memory: MemoryUsage(totalBytes: 16, usedBytes: 8, compressedBytes: 0, swapUsedBytes: 0, pressure: .elevated),
            topByCPU: [], topByMemory: [],
            battery: BatteryStatus(chargePercent: 50, isCharging: false, isPluggedIn: false, minutesRemaining: nil, cycleCount: 10, healthPercent: 91),
            thermal: .normal, isLowPowerMode: false,
            diskTotalBytes: 500, diskAvailableBytes: 200, uptimeSeconds: 0
        )

        let observation = HealthObservation.from(report: report, apps: apps, sample: sample)

        XCTAssertEqual(observation.inventory.apps.map { $0.key }, ["com.example.Notes", "/Applications/Tool.app"])
        XCTAssertEqual(observation.inventory.apps[0].detail, "2.0")
        XCTAssertEqual(observation.inventory.backgroundItems.map { $0.name }, ["com.odd.agent", "com.fine.agent"])
        XCTAssertEqual(observation.inventory.extensions.first?.detail, "Chrome")
        XCTAssertEqual(observation.inventory.protectionsOff, ["system-integrity-protection", "filevault"])
        XCTAssertEqual(observation.attentionCount, 1, "Only what is outside macOS's own protections")
        XCTAssertEqual(observation.memoryPressure, .elevated)
        XCTAssertEqual(observation.batteryHealthPercent, 91)
        XCTAssertEqual(observation.diskAvailableBytes, 200)
    }

    #if os(macOS)
    func testThisMacCanBeObserved() {
        let observation = HealthObservation.gather()
        XCTAssertFalse(observation.inventory.apps.isEmpty)
        XCTAssertNotNil(observation.diskTotalBytes)
        let score = observation.score
        XCTAssertGreaterThanOrEqual(score.total, 0)
        XCTAssertLessThanOrEqual(score.total, 100)
        XCTAssertFalse(score.parts.isEmpty)
    }
    #endif
}
