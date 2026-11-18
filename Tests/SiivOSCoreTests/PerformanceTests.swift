import XCTest
@testable import SiivOSCore

final class KnownProcessesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.overrideLanguage = .english
    }

    func testWellKnownPartsOfMacOSAreExplainedAndOthersAreLeftAlone() {
        XCTAssertTrue(KnownProcesses.explanation(for: "mds_stores")?.contains("Spotlight") ?? false)
        XCTAssertTrue(KnownProcesses.explanation(for: "backupd")?.contains("Time Machine") ?? false)
        XCTAssertTrue(KnownProcesses.explanation(for: "photoanalysisd")?.contains("Photos") ?? false)
        XCTAssertTrue(KnownProcesses.explanation(for: "cloudd")?.contains("iCloud") ?? false)
        XCTAssertNotNil(KnownProcesses.explanation(for: "softwareupdated"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "syspolicyd"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "coreaudiod"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "launchd"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "WindowServer"), "Upper and lower case do not matter")
        XCTAssertNil(KnownProcesses.explanation(for: "Safari"), "SiivOS adds nothing where the name already says it")
    }
}

final class PerformanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        L10n.overrideLanguage = .english
    }

    // MARK: - Reading the tools' output

    func testProcessesAreReadAndAddedUpByName() {
        let output = """
            1   0.0   15680 launchd
          412  12.5  204800 Google Chrome Helper (Renderer)
          413   7,5  102400 Google Chrome Helper (Renderer)
          500 101.3 1048576 Final Cut Pro
        this line is not a process
          600   abc    1024 broken
        """
        let processes = PerformanceParsers.processes(fromPS: output)

        XCTAssertEqual(processes.map { $0.name }, ["launchd", "Google Chrome Helper (Renderer)", "Final Cut Pro"])
        let helpers = processes[1]
        XCTAssertEqual(helpers.count, 2)
        XCTAssertEqual(helpers.cpuPercent, 20.0, accuracy: 0.001)
        XCTAssertEqual(helpers.memoryBytes, 307_200 * 1_024)
        XCTAssertEqual(processes[2].cpuPercent, 101.3, accuracy: 0.001)
        XCTAssertEqual(processes[0].count, 1)
    }

    private let vmStat = """
    Mach Virtual Memory Statistics: (page size of 16384 bytes)
    Pages free:                                5000.
    Pages active:                            400000.
    Pages inactive:                          300000.
    Pages speculative:                         2000.
    Pages throttled:                              0.
    Pages wired down:                        150000.
    Pages purgeable:                          20000.
    "Translation faults":                 123456789.
    Pages copy-on-write:                    1234567.
    Pages occupied by compressor:            100000.
    File-backed pages:                       350000.
    Anonymous pages:                         520000.
    """

    func testMemoryInUseIsAppMemoryPlusWiredPlusCompressed() throws {
        let total: Int64 = 36 * 1_073_741_824
        let memory = try XCTUnwrap(
            PerformanceParsers.memory(fromVMStat: vmStat, totalBytes: total, swapUsedBytes: 5, pressure: .elevated)
        )

        // (520000 - 20000) + 150000 + 100000 pages of 16384 bytes.
        XCTAssertEqual(memory.usedBytes, 750_000 * 16_384)
        XCTAssertEqual(memory.compressedBytes, 100_000 * 16_384)
        XCTAssertEqual(memory.totalBytes, total)
        XCTAssertEqual(memory.swapUsedBytes, 5)
        XCTAssertEqual(memory.pressure, .elevated)
        XCTAssertEqual(memory.usedFraction, Double(750_000 * 16_384) / Double(total), accuracy: 0.0001)
    }

    func testUnreadableMemoryOutputGivesNothing() {
        XCTAssertNil(PerformanceParsers.memory(fromVMStat: "", totalBytes: 1, swapUsedBytes: 0, pressure: .normal))
        XCTAssertNil(PerformanceParsers.memory(fromVMStat: "page size of 4096 bytes", totalBytes: 1, swapUsedBytes: 0, pressure: .normal))
    }

    func testSwapAndPressureAreRead() {
        XCTAssertEqual(
            PerformanceParsers.swapUsedBytes(fromSysctl: "total = 2048.00M  used = 1024.50M  free = 1023.50M  (encrypted)"),
            Int64(1024.5 * 1_048_576)
        )
        XCTAssertEqual(PerformanceParsers.swapUsedBytes(fromSysctl: "total = 3.00G  used = 1.50G  free = 1.50G"), Int64(1.5 * 1_073_741_824))
        XCTAssertEqual(PerformanceParsers.swapUsedBytes(fromSysctl: "total = 0.00M  used = 0.00M  free = 0.00M"), 0)
        XCTAssertNil(PerformanceParsers.swapUsedBytes(fromSysctl: "nonsense"))

        XCTAssertEqual(PerformanceParsers.pressure(fromSysctl: "1\n"), .normal)
        XCTAssertEqual(PerformanceParsers.pressure(fromSysctl: "2\n"), .elevated)
        XCTAssertEqual(PerformanceParsers.pressure(fromSysctl: "4\n"), .high)
        XCTAssertEqual(PerformanceParsers.pressure(fromSysctl: ""), .normal)
    }

    func testBatteryIsReadWhileDischarging() throws {
        let output = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=23855203)\t85%; discharging; 4:12 remaining present: true
        """
        let battery = try XCTUnwrap(PerformanceParsers.battery(fromPMSet: output, health: (215, 91)))

        XCTAssertEqual(battery.chargePercent, 85)
        XCTAssertFalse(battery.isCharging)
        XCTAssertFalse(battery.isPluggedIn)
        XCTAssertEqual(battery.minutesRemaining, 252)
        XCTAssertEqual(battery.cycleCount, 215)
        XCTAssertEqual(battery.healthPercent, 91)
    }

    func testBatteryIsReadWhileChargingAndWhenFull() throws {
        let charging = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=1)\t42%; charging; 1:05 remaining present: true
        """
        let chargingStatus = try XCTUnwrap(PerformanceParsers.battery(fromPMSet: charging, health: (nil, nil)))
        XCTAssertTrue(chargingStatus.isCharging)
        XCTAssertTrue(chargingStatus.isPluggedIn)
        XCTAssertEqual(chargingStatus.minutesRemaining, 65)
        XCTAssertNil(chargingStatus.cycleCount)

        let full = """
        Now drawing from 'AC Power'
         -InternalBattery-0 (id=1)\t100%; charged; 0:00 remaining present: true
        """
        let fullStatus = try XCTUnwrap(PerformanceParsers.battery(fromPMSet: full, health: (nil, nil)))
        XCTAssertEqual(fullStatus.chargePercent, 100)
        XCTAssertFalse(fullStatus.isCharging)
        XCTAssertNil(fullStatus.minutesRemaining)

        let noEstimate = """
        Now drawing from 'Battery Power'
         -InternalBattery-0 (id=1)\t77%; discharging; (no estimate) present: true
        """
        XCTAssertNil(try XCTUnwrap(PerformanceParsers.battery(fromPMSet: noEstimate, health: (nil, nil))).minutesRemaining)
    }

    func testAMacWithoutABatteryHasNoBatteryStatus() {
        XCTAssertNil(PerformanceParsers.battery(fromPMSet: "Now drawing from 'AC Power'\n", health: (nil, nil)))
    }

    func testBatteryHealthIsReadFromBothKindsOfMac() {
        let appleSilicon = """
              "CycleCount" = 215
              "AppleRawMaxCapacity" = 4382
              "MaxCapacity" = 100
              "DesignCapacity" = 4790
        """
        let newer = PerformanceParsers.batteryHealth(fromIOReg: appleSilicon)
        XCTAssertEqual(newer.cycleCount, 215)
        XCTAssertEqual(newer.healthPercent, 91)

        let intel = """
              "CycleCount" = 800
              "MaxCapacity" = 5000
              "DesignCapacity" = 6669
        """
        let older = PerformanceParsers.batteryHealth(fromIOReg: intel)
        XCTAssertEqual(older.cycleCount, 800)
        XCTAssertEqual(older.healthPercent, 75)

        let nothing = PerformanceParsers.batteryHealth(fromIOReg: "")
        XCTAssertNil(nothing.cycleCount)
        XCTAssertNil(nothing.healthPercent)
    }

    func testProcessorUseComesFromTheDifferenceBetweenTwoReadings() {
        let earlier = CPUTicks(busy: 1_000, idle: 9_000)
        XCTAssertEqual(CPUTicks.usedFraction(from: earlier, to: CPUTicks(busy: 1_250, idle: 9_750)) ?? -1, 0.25, accuracy: 0.0001)
        XCTAssertNil(CPUTicks.usedFraction(from: earlier, to: earlier), "No time has passed")
        XCTAssertNil(CPUTicks.usedFraction(from: earlier, to: CPUTicks(busy: 10, idle: 10)), "Counters went backwards")
    }

    func testRunningACommandReturnsItsOutput() {
        XCTAssertEqual(SystemCommand.output(of: "/bin/echo", ["hello"]), "hello\n")
        XCTAssertNil(SystemCommand.output(of: "/no/such/tool", []))
    }

    // MARK: - Diagnoses

    private func sample(
        cpu: Double? = 0.10,
        pressure: MemoryUsage.Pressure = .normal,
        topCPU: [ProcessUsage] = [],
        topMemory: [ProcessUsage] = [],
        battery: BatteryStatus? = nil,
        thermal: ThermalLevel = .normal,
        lowPower: Bool = false,
        diskTotal: Int64? = 500_000_000_000,
        diskAvailable: Int64? = 250_000_000_000,
        uptimeDays: Double = 1
    ) -> PerformanceSample {
        PerformanceSample(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            cpuUsedFraction: cpu,
            coreCount: 8,
            memory: MemoryUsage(
                totalBytes: 16_000_000_000,
                usedBytes: 8_000_000_000,
                compressedBytes: 0,
                swapUsedBytes: 0,
                pressure: pressure
            ),
            topByCPU: topCPU,
            topByMemory: topMemory,
            battery: battery,
            thermal: thermal,
            isLowPowerMode: lowPower,
            diskTotalBytes: diskTotal,
            diskAvailableBytes: diskAvailable,
            uptimeSeconds: uptimeDays * 86_400
        )
    }

    private func ids(_ samples: [PerformanceSample]) -> [String] {
        PerformanceDiagnosis.evaluate(samples).map { $0.id }
    }

    func testAHealthyMacGetsOneReassuringDiagnosis() {
        let diagnoses = PerformanceDiagnosis.evaluate(Array(repeating: sample(), count: 5))
        XCTAssertEqual(diagnoses.map { $0.id }, ["all-good"])
        XCTAssertEqual(diagnoses[0].level, .good)
        XCTAssertTrue(PerformanceDiagnosis.evaluate([]).isEmpty)
    }

    func testAFullDiskIsNoticedAndPointsToCleanup() {
        let nearlyFull = PerformanceDiagnosis.evaluate([sample(diskAvailable: 20_000_000_000)])
        XCTAssertEqual(nearlyFull.map { $0.id }, ["disk-nearly-full"])
        XCTAssertEqual(nearlyFull[0].level, .attention)
        XCTAssertEqual(nearlyFull[0].suggestion, .openCleanup)

        XCTAssertEqual(ids([sample(diskAvailable: 80_000_000_000)]), ["disk-getting-full"])
        // A small disk with a fair share free still has too little room in absolute terms.
        XCTAssertEqual(ids([sample(diskTotal: 30_000_000_000, diskAvailable: 9_000_000_000)]), ["disk-nearly-full"])
        XCTAssertEqual(ids([sample(diskTotal: nil, diskAvailable: nil)]), ["all-good"])
    }

    func testMemoryPressureNeedsMoreThanOneBriefReading() {
        let calm = sample()
        let tight = sample(pressure: .elevated, topMemory: [ProcessUsage(name: "Browser", cpuPercent: 1, memoryBytes: 9_000_000_000)])
        let heavy = sample(pressure: .high)

        XCTAssertEqual(ids([calm, calm, tight]), ["all-good"], "One reading out of three is a blip")
        XCTAssertEqual(ids([calm, tight, tight]), ["memory-pressure-elevated"])
        XCTAssertEqual(ids([tight, heavy, heavy]), ["memory-pressure-high"])
        XCTAssertEqual(ids([tight]), ["memory-pressure-elevated"], "With a single reading there is nothing to compare with")

        let diagnosis = PerformanceDiagnosis.evaluate([tight, tight, tight])[0]
        XCTAssertTrue(diagnosis.explanation.contains("Browser"))
    }

    func testARestartIsSuggestedOnlyWhenMemoryIsTightAfterALongTime() {
        let tightAndOld = sample(pressure: .elevated, uptimeDays: 23)
        XCTAssertEqual(ids([tightAndOld, tightAndOld]), ["memory-pressure-elevated", "restart-may-help"])
        XCTAssertEqual(ids([sample(uptimeDays: 90)]), ["all-good"], "A long time without restarting is not a problem by itself")
    }

    func testABusyProcessorIsNoticedOnlyWhenItLasts() {
        let hog = ProcessUsage(name: "Exporter", cpuPercent: 640, memoryBytes: 1)
        let busy = sample(cpu: 0.92, topCPU: [hog])

        XCTAssertEqual(ids([sample(), sample(), busy]), ["all-good"], "One busy reading among calm ones is a spike")
        XCTAssertEqual(ids([busy, busy]), ["all-good"], "Too few readings to tell")

        let diagnoses = PerformanceDiagnosis.evaluate([busy, busy, busy, busy])
        XCTAssertEqual(diagnoses.map { $0.id }, ["processor-busy"])
        XCTAssertTrue(diagnoses[0].explanation.contains("Exporter"))
    }

    func testOneProgramKeepingACoreBusyIsANote() {
        let stuck = sample(cpu: 0.14, topCPU: [ProcessUsage(name: "Helper", cpuPercent: 99, memoryBytes: 1)])
        let diagnoses = PerformanceDiagnosis.evaluate([stuck, stuck, stuck])

        XCTAssertEqual(diagnoses.map { $0.id }, ["one-program-working-hard"])
        XCTAssertEqual(diagnoses[0].level, .note)
        XCTAssertTrue(diagnoses[0].title.contains("Helper"))

        let brief = sample(cpu: 0.14, topCPU: [ProcessUsage(name: "Helper", cpuPercent: 30, memoryBytes: 1)])
        XCTAssertEqual(ids([stuck, brief, stuck]), ["all-good"])
    }

    func testHeatLowPowerModeAndAnAgedBatteryAreNoticed() {
        XCTAssertEqual(ids([sample(thermal: .hot)]), ["running-hot"])
        XCTAssertEqual(ids([sample(thermal: .warm)]), ["all-good"])
        XCTAssertEqual(ids([sample(lowPower: true)]), ["low-power-mode"])

        let aged = BatteryStatus(chargePercent: 60, isCharging: false, isPluggedIn: false, minutesRemaining: 90, cycleCount: 812, healthPercent: 74)
        let agedDiagnoses = PerformanceDiagnosis.evaluate([sample(battery: aged)])
        XCTAssertEqual(agedDiagnoses.map { $0.id }, ["battery-aged"])
        XCTAssertTrue(agedDiagnoses[0].explanation.contains("812"))

        let healthy = BatteryStatus(chargePercent: 60, isCharging: false, isPluggedIn: false, minutesRemaining: 90, cycleCount: 50, healthPercent: 97)
        XCTAssertEqual(ids([sample(battery: healthy)]), ["all-good"])
    }

    func testTheMostImportantDiagnosisComesFirst() {
        let troubled = sample(lowPower: true, diskAvailable: 5_000_000_000)
        XCTAssertEqual(ids([troubled]), ["disk-nearly-full", "low-power-mode"])

        let hotAndAged = sample(
            battery: BatteryStatus(chargePercent: 50, isCharging: false, isPluggedIn: false, minutesRemaining: nil, cycleCount: nil, healthPercent: 70),
            thermal: .hot,
            lowPower: true
        )
        XCTAssertEqual(ids([hotAndAged]), ["running-hot", "low-power-mode", "battery-aged"])
    }

    func testWellKnownSystemProgramsAreExplained() {
        XCTAssertNotNil(KnownProcesses.explanation(for: "kernel_task"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "WindowServer"))
        XCTAssertNotNil(KnownProcesses.explanation(for: "mds_stores"))
        XCTAssertNil(KnownProcesses.explanation(for: "Some Unknown App"))
    }

    // MARK: - On a real Mac

    #if os(macOS)
    func testTheSamplerReadsThisMac() {
        let sampler = PerformanceSampler()
        let first = sampler.sample()
        XCTAssertNil(first.cpuUsedFraction, "The first reading has nothing to compare with")
        XCTAssertGreaterThan(first.coreCount, 0)
        XCTAssertFalse(first.topByMemory.isEmpty)
        let memory = try? XCTUnwrap(first.memory)
        XCTAssertGreaterThan(memory?.usedBytes ?? 0, 0)
        XCTAssertLessThanOrEqual(memory?.usedBytes ?? 0, memory?.totalBytes ?? 0)
        XCTAssertNotNil(first.diskTotalBytes)

        Thread.sleep(forTimeInterval: 0.3)
        let second = sampler.sample()
        let cpu = second.cpuUsedFraction ?? -1
        XCTAssertGreaterThanOrEqual(cpu, 0)
        XCTAssertLessThanOrEqual(cpu, 1)
        XCTAssertFalse(PerformanceDiagnosis.evaluate([first, second]).isEmpty)
    }
    #endif
}
