import Foundation

/// Where SiivOS keeps its own data on this Mac.
public enum SiivOSData {
    /// `~/Library/Application Support/SiivOS`. Nothing is created by asking for it.
    public static func standardDirectory() -> URL {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("SiivOS", isDirectory: true)
    }
}

/// The switch for the agent door. It is off until the user turns it on in Settings.
///
/// The switch is a small file in SiivOS's own folder, because the app and the
/// command-line tool are two separate programs and both need to read it. It is a
/// courtesy, not a lock: it controls what SiivOS's own tool will answer, and cannot stop
/// other programs the user runs from reading the same Mac.
public struct AgentDoorSwitch: Sendable {
    public let fileURL: URL

    public init(dataDirectory: URL) {
        fileURL = dataDirectory.appendingPathComponent("agent-door.json")
    }

    public static func standard() -> AgentDoorSwitch {
        AgentDoorSwitch(dataDirectory: SiivOSData.standardDirectory())
    }

    private struct Stored: Codable {
        var enabled: Bool
    }

    /// True when the user has turned the door on. A missing or unreadable file means off.
    public var isOn: Bool {
        guard let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode(Stored.self, from: data)
        else {
            return false
        }
        return stored.enabled
    }

    public func set(_ isOn: Bool) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Stored(enabled: isOn))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Answers questions about this Mac for an AI agent the user already uses, through the
/// `siivos-cli` command-line tool.
///
/// The door only reads. It can say what SiivOS found, what has changed and why the Mac
/// is slow, in the same words the app uses. It cannot remove, move or change anything,
/// and it does not use the network. Removing stays in the app, where a person reads the
/// explanation and confirms.
public struct AgentDoor: Sendable {
    /// What the tool prints and the code it ends with: 0 when it answered.
    public struct Reply: Equatable, Sendable {
        public let output: String
        public let exitCode: Int32
    }

    /// Where the door gets its facts. Tests put pretend facts here; the real ones run
    /// SiivOS's usual checks, all of which only read.
    public struct Sources: Sendable {
        public var snapshot: @Sendable () -> SystemSnapshot
        public var scan: @Sendable () -> ScanReport
        public var protection: @Sendable () -> ProtectionReport
        /// Readings a moment apart, oldest first. Processor use needs two.
        public var performance: @Sendable () -> [PerformanceSample]
        public var apps: @Sendable () -> [AppInfo]

        public init(
            snapshot: @escaping @Sendable () -> SystemSnapshot,
            scan: @escaping @Sendable () -> ScanReport,
            protection: @escaping @Sendable () -> ProtectionReport,
            performance: @escaping @Sendable () -> [PerformanceSample],
            apps: @escaping @Sendable () -> [AppInfo]
        ) {
            self.snapshot = snapshot
            self.scan = scan
            self.protection = protection
            self.performance = performance
            self.apps = apps
        }

        /// The real checks, looking at this Mac.
        ///
        /// - Parameter progress: Called with a line saying what is being looked at.
        ///   Some checks take a while on a full disk, and without this the tool would
        ///   look stuck. The lines are for a person watching, not part of the answer.
        public static func live(homeDirectory: URL, progress: (@Sendable (String) -> Void)? = nil) -> Sources {
            Sources(
                snapshot: { SystemSnapshot.current() },
                scan: {
                    // Caches and logs of apps that are open are held back, as in the app.
                    ScanEngine.clutter(homeDirectory: homeDirectory, runningApps: RunningApp.current()).run { title in
                        progress?(tr("Checking: %1$@…", title))
                    }
                },
                protection: {
                    ProtectionCheck.run(homeDirectory: homeDirectory) { title in
                        progress?(tr("Checking: %1$@…", title))
                    }
                },
                performance: {
                    progress?(tr("Taking readings…"))
                    let sampler = PerformanceSampler()
                    let first = sampler.sample()
                    Thread.sleep(forTimeInterval: 1)
                    return [first, sampler.sample()]
                },
                apps: {
                    progress?(tr("Measuring apps…"))
                    return AppInventory.load(directories: InstalledApps.standardDirectories(homeDirectory: homeDirectory))
                }
            )
        }
    }

    /// The version the tool reports. Keep in step with `Scripts/make-app.sh`.
    public static let version = "0.1.0"
    /// The name of the command-line tool.
    public static let toolName = "siivos-cli"

    private let dataDirectory: URL
    private let sources: Sources
    private let now: @Sendable () -> Date

    public init(dataDirectory: URL, sources: Sources, now: @escaping @Sendable () -> Date = { Date() }) {
        self.dataDirectory = dataDirectory
        self.sources = sources
        self.now = now
    }

    /// The door the tool uses: SiivOS's own folder and the real checks.
    ///
    /// - Parameter progress: Called with a line saying what is being looked at.
    public static func standard(progress: (@Sendable (String) -> Void)? = nil) -> AgentDoor {
        AgentDoor(
            dataDirectory: SiivOSData.standardDirectory(),
            sources: .live(homeDirectory: URL(fileURLWithPath: NSHomeDirectory()), progress: progress)
        )
    }

    // MARK: - Answering

    /// The questions the door answers, in the order the help lists them.
    public enum Command: String, CaseIterable, Sendable {
        case status
        case overview
        case health
        case changes
        case cleanup
        case performance
        case protection
        case apps
        case history
        case mcp
        case help

        /// What the command answers, in one line.
        public var summary: String {
            switch self {
            case .status: return tr("Whether the door is on, and where SiivOS keeps its data.")
            case .overview: return tr("Disk space, memory, the health score and what waits in the holding area.")
            case .health: return tr("The health score with the reason for every point, and recent readings.")
            case .changes: return tr("What has changed on this Mac lately. Add --days 7 for a different number of days.")
            case .cleanup: return tr("What could be removed, each item labelled Safe to remove or Check first. Add --limit 50 for more items per group.")
            case .performance: return tr("Processor, memory and battery right now, with what SiivOS makes of them.")
            case .protection: return tr("The protection built into macOS, background items, browser extensions and profiles.")
            case .apps: return tr("Installed apps with their size and last use, largest first. Add --limit 50 for more.")
            case .history: return tr("What SiivOS itself has changed, and what can still be put back.")
            case .mcp: return tr("Offer these questions to an AI agent as tools, over the Model Context Protocol. The agent starts this itself.")
            case .help: return tr("This list.")
            }
        }
    }

    /// Answers one question. `arguments` are the words after the tool's name.
    public func answer(_ arguments: [String]) -> Reply {
        guard let word = arguments.first else {
            return Reply(output: help, exitCode: 0)
        }
        guard let command = Command(rawValue: word.lowercased()) else {
            return Reply(output: tr("SiivOS has no answer for: %1$@", word) + "\n\n" + help, exitCode: 64)
        }
        let options = Self.options(in: Array(arguments.dropFirst()))
        let isOn = AgentDoorSwitch(dataDirectory: dataDirectory).isOn

        switch command {
        case .help:
            return Reply(output: help, exitCode: 0)
        case .mcp:
            // The tool itself keeps the conversation going; see AgentDoorServer.
            return Reply(output: tr("This is meant to be started by an AI agent, which then talks to it. To try the questions yourself, use the other words in the list."), exitCode: 0)
        case .status:
            return json(StatusAnswer(
                version: Self.version,
                door: isOn ? "on" : "off",
                note: isOn ? Self.readOnlyNote : Self.offMessage,
                dataFolder: dataDirectory.path,
                commands: Command.allCases.map { $0.rawValue }
            ))
        default:
            break
        }

        // Everything past this point looks at the Mac, so the door must be on.
        guard isOn else {
            return Reply(output: Self.offMessage, exitCode: 2)
        }
        switch command {
        case .overview: return json(overview())
        case .health: return json(health())
        case .changes: return json(changes(days: max(1, options["days"] ?? 30)))
        case .cleanup: return json(cleanup(limit: max(1, options["limit"] ?? 20)))
        case .performance: return json(performance())
        case .protection: return json(protection())
        case .apps: return json(apps(limit: max(1, options["limit"] ?? 25)))
        case .history: return history()
        case .status, .help, .mcp: return Reply(output: help, exitCode: 0)
        }
    }

    /// What the tool says when the door is off.
    static var offMessage: String {
        tr("The agent door is off. To let an AI agent ask SiivOS questions, open SiivOS, choose Settings and turn on \"Let AI agents ask SiivOS questions\".")
    }

    /// The reminder that goes out with answers.
    static var readOnlyNote: String {
        tr("This tool only reads. To remove anything, open SiivOS, where every change is explained first and can be undone.")
    }

    private var help: String {
        var lines = [
            tr("%1$@ answers questions about this Mac for an AI agent. It only reads and never changes anything.", Self.toolName),
            "",
            tr("Usage: %1$@ <question>", Self.toolName),
            ""
        ]
        for command in Command.allCases {
            lines.append("  " + command.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0) + command.summary)
        }
        lines.append("")
        lines.append(tr("Answers are in JSON. Sizes are in bytes, with a readable form next to them."))
        return lines.joined(separator: "\n")
    }

    /// Reads "--name 12" pairs. Anything else is ignored.
    static func options(in arguments: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            if word.hasPrefix("--"), index + 1 < arguments.count, let value = Int(arguments[index + 1]) {
                result[String(word.dropFirst(2))] = value
                index += 2
            } else {
                index += 1
            }
        }
        return result
    }

    private func json<Answer: Encodable>(_ answer: Answer) -> Reply {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(answer), let text = String(data: data, encoding: .utf8) else {
            return Reply(output: tr("The answer could not be written out."), exitCode: 1)
        }
        return Reply(output: text, exitCode: 0)
    }

    private static func readable(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // "0 KB", not "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Status

    private struct StatusAnswer: Encodable {
        let version: String
        let door: String
        let note: String
        let dataFolder: String
        let commands: [String]
    }

    // MARK: - Overview

    private struct OverviewAnswer: Encodable {
        struct Disk: Encodable {
            let totalBytes: Int64?
            let availableBytes: Int64?
            let total: String?
            let available: String?
            let freePercent: Int?
        }
        struct Health: Encodable {
            let score: Int
            let readingTaken: Date
        }

        let macOS: String
        let processorCores: Int
        let memoryBytes: Int64
        let memory: String
        let hoursSinceRestart: Double
        let disk: Disk
        /// The last reading the app saved, or nothing if the app has not taken one yet.
        let health: Health?
        let holdingAreaBytes: Int64
        let holdingArea: String
        let note: String
    }

    private func overview() -> OverviewAnswer {
        let snapshot = sources.snapshot()
        let lastReading = HealthStore(fileURL: dataDirectory.appendingPathComponent("health-history.json")).load().readings.last
        let held = ownRecords().reduce(Int64(0)) { $0 + $1.heldBytes }
        var freePercent: Int?
        if let total = snapshot.diskTotalBytes, total > 0, let available = snapshot.diskAvailableBytes {
            freePercent = Int((Double(available) / Double(total) * 100).rounded())
        }
        let memoryBytes = Int64(clamping: snapshot.physicalMemoryBytes)
        return OverviewAnswer(
            macOS: snapshot.osVersion,
            processorCores: snapshot.processorCount,
            memoryBytes: memoryBytes,
            memory: ByteCountFormatter.string(fromByteCount: memoryBytes, countStyle: .memory),
            hoursSinceRestart: (snapshot.uptimeSeconds / 360).rounded() / 10,
            disk: OverviewAnswer.Disk(
                totalBytes: snapshot.diskTotalBytes,
                availableBytes: snapshot.diskAvailableBytes,
                total: snapshot.diskTotalBytes.map(Self.readable),
                available: snapshot.diskAvailableBytes.map(Self.readable),
                freePercent: freePercent
            ),
            health: lastReading.map { OverviewAnswer.Health(score: $0.score, readingTaken: $0.date) },
            holdingAreaBytes: held,
            holdingArea: Self.readable(held),
            note: Self.readOnlyNote
        )
    }

    /// What SiivOS has changed, oldest first. Read straight from the history file, so
    /// that asking never creates or changes anything.
    private func ownRecords() -> [ActionRecord] {
        (try? ActionLog(fileURL: dataDirectory.appendingPathComponent("action-log.json")).load()) ?? []
    }

    // MARK: - Health

    private struct HealthAnswer: Encodable {
        struct Part: Encodable {
            let id: String
            let title: String
            let points: Int
            let maximum: Int
            let explanation: String
        }
        struct Reading: Encodable {
            let date: Date
            let score: Int
            let diskAvailableBytes: Int64?
        }

        /// The score right now, out of 100.
        let score: Int
        let parts: [Part]
        /// The last readings the app saved, oldest first.
        let recentReadings: [Reading]
        let howItIsCounted: String
    }

    private func health() -> HealthAnswer {
        // A fresh look at the Mac, for the reasons behind the score. It is not saved:
        // only the app adds readings to the history.
        let samples = sources.performance()
        // The list of apps is left out: the score does not depend on it, and measuring
        // every app would make this answer slow.
        let observation = HealthObservation.from(
            report: sources.protection(),
            apps: [],
            sample: samples.last ?? PerformanceSample.unknown(at: now())
        )
        let score = observation.score
        let history = HealthStore(fileURL: dataDirectory.appendingPathComponent("health-history.json")).load()
        return HealthAnswer(
            score: score.total,
            parts: score.parts.map {
                HealthAnswer.Part(id: $0.id, title: $0.title, points: $0.points, maximum: $0.maximum, explanation: $0.explanation)
            },
            recentReadings: history.readings.suffix(30).map {
                HealthAnswer.Reading(date: $0.date, score: $0.score, diskAvailableBytes: $0.diskAvailableBytes)
            },
            howItIsCounted: tr("The score counts what really affects a Mac, free disk space most of all. Memory that is simply in use costs nothing, and neither does a firewall that is off, because that is how macOS comes.")
        )
    }

    // MARK: - Changes

    private struct ChangesAnswer: Encodable {
        struct Change: Encodable {
            let date: Date
            /// What kind of change it was, for example "appAdded", or "siivosAction" for
            /// something SiivOS itself did.
            let kind: String
            let title: String
            let explanation: String?
            /// True for changes worth a second glance.
            let worthALook: Bool
        }

        let days: Int
        /// Newest first.
        let changes: [Change]
        let note: String
    }

    private func changes(days: Int) -> ChangesAnswer {
        let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
        let history = HealthStore(fileURL: dataDirectory.appendingPathComponent("health-history.json")).load()
        var all = history.events.filter { $0.date >= cutoff }.map {
            ChangesAnswer.Change(date: $0.date, kind: $0.kind.rawValue, title: $0.title, explanation: $0.explanation, worthALook: $0.isNoteworthy)
        }
        all += ownRecords().filter { $0.date >= cutoff }.map {
            ChangesAnswer.Change(date: $0.date, kind: "siivosAction", title: $0.title, explanation: $0.explanation, worthALook: false)
        }
        return ChangesAnswer(
            days: days,
            changes: all.sorted { $0.date > $1.date },
            note: tr("SiivOS notices a change when it takes a reading, so the time shown is when it noticed, not the moment it happened.")
        )
    }

    // MARK: - Cleanup

    private struct CleanupAnswer: Encodable {
        struct Item: Encodable {
            /// What the item is, where its file name says little.
            let name: String?
            let path: String
            let sizeBytes: Int64
            let size: String
            /// "safeToRemove" or "checkFirst".
            let label: String
            let labelReason: String
            let explanation: String
            /// Set when the item should not be removed right now, for example because
            /// the app it belongs to is open. Such items are not counted as safe to remove.
            let heldBack: String?
        }
        struct Group: Encodable {
            let id: String
            let title: String
            let summary: String
            let totalBytes: Int64
            let total: String
            let itemCount: Int
            /// The largest items, up to the limit asked for.
            let items: [Item]
            let couldNotFinish: String?
        }

        let safeToRemoveBytes: Int64
        let safeToRemove: String
        let groups: [Group]
        let note: String
    }

    private func cleanup(limit: Int) -> CleanupAnswer {
        let report = sources.scan()
        return CleanupAnswer(
            safeToRemoveBytes: report.safeToRemoveBytes,
            safeToRemove: Self.readable(report.safeToRemoveBytes),
            groups: report.sections.map { section in
                CleanupAnswer.Group(
                    id: section.id,
                    title: section.title,
                    summary: section.summary,
                    totalBytes: section.totalBytes,
                    total: Self.readable(section.totalBytes),
                    itemCount: section.findings.count,
                    items: section.findings.prefix(limit).map { finding in
                        CleanupAnswer.Item(
                            name: finding.displayName,
                            path: finding.url.path,
                            sizeBytes: finding.sizeBytes,
                            size: Self.readable(finding.sizeBytes),
                            label: finding.safety.rawValue,
                            labelReason: finding.safetyReason,
                            explanation: finding.explanation,
                            heldBack: finding.heldBackReason
                        )
                    },
                    couldNotFinish: section.failure
                )
            },
            note: Self.readOnlyNote
        )
    }

    // MARK: - Performance

    private struct PerformanceAnswer: Encodable {
        struct Memory: Encodable {
            let totalBytes: Int64
            let usedBytes: Int64
            /// "normal", "elevated" or "high". This says more about speed than the amount in use.
            let pressure: String
            let movedToDiskBytes: Int64
        }
        struct Battery: Encodable {
            let chargePercent: Int
            let isCharging: Bool
            let isPluggedIn: Bool
            let healthPercent: Int?
            let chargeCycles: Int?
        }
        struct Program: Encodable {
            let name: String
            /// Share of the whole processor, from 0 to 100.
            let processorPercent: Double
            let memoryBytes: Int64
            /// What the program is, where SiivOS knows.
            let whatItIs: String?
        }
        struct Finding: Encodable {
            let id: String
            /// "good", "note" or "attention".
            let level: String
            let title: String
            let explanation: String
        }

        let processorPercent: Int?
        let processorCores: Int
        let memory: Memory?
        let battery: Battery?
        /// "normal", "warm" or "hot".
        let temperature: String
        let lowPowerMode: Bool
        let busiestPrograms: [Program]
        let programsUsingMostMemory: [Program]
        /// What SiivOS makes of the readings, most important first.
        let findings: [Finding]
    }

    private func performance() -> PerformanceAnswer {
        let samples = sources.performance()
        let sample = samples.last ?? PerformanceSample.unknown(at: now())
        let cores = Double(max(1, sample.coreCount))
        func program(_ usage: ProcessUsage) -> PerformanceAnswer.Program {
            PerformanceAnswer.Program(
                name: usage.name,
                processorPercent: (usage.cpuPercent / cores * 10).rounded() / 10,
                memoryBytes: usage.memoryBytes,
                whatItIs: KnownProcesses.explanation(for: usage.name)
            )
        }
        return PerformanceAnswer(
            processorPercent: sample.cpuUsedFraction.map { Int((min(1, max(0, $0)) * 100).rounded()) },
            processorCores: sample.coreCount,
            memory: sample.memory.map {
                PerformanceAnswer.Memory(
                    totalBytes: $0.totalBytes,
                    usedBytes: $0.usedBytes,
                    pressure: Self.name(of: $0.pressure),
                    movedToDiskBytes: $0.swapUsedBytes
                )
            },
            battery: sample.battery.map {
                PerformanceAnswer.Battery(
                    chargePercent: $0.chargePercent,
                    isCharging: $0.isCharging,
                    isPluggedIn: $0.isPluggedIn,
                    healthPercent: $0.healthPercent,
                    chargeCycles: $0.cycleCount
                )
            },
            temperature: Self.name(of: sample.thermal),
            lowPowerMode: sample.isLowPowerMode,
            busiestPrograms: sample.topByCPU.map(program),
            programsUsingMostMemory: sample.topByMemory.map(program),
            findings: PerformanceDiagnosis.evaluate(samples).map {
                PerformanceAnswer.Finding(id: $0.id, level: Self.name(of: $0.level), title: $0.title, explanation: $0.explanation)
            }
        )
    }

    private static func name(of pressure: MemoryUsage.Pressure) -> String {
        switch pressure {
        case .normal: return "normal"
        case .elevated: return "elevated"
        case .high: return "high"
        }
    }

    private static func name(of thermal: ThermalLevel) -> String {
        switch thermal {
        case .normal: return "normal"
        case .warm: return "warm"
        case .hot: return "hot"
        }
    }

    private static func name(of level: Diagnosis.Level) -> String {
        switch level {
        case .good: return "good"
        case .note: return "note"
        case .attention: return "attention"
        }
    }

    private static func name(of level: ProtectionFinding.Level) -> String {
        switch level {
        case .fine: return "fine"
        case .note: return "note"
        case .attention: return "attention"
        }
    }

    // MARK: - Protection

    private struct ProtectionAnswer: Encodable {
        struct Finding: Encodable {
            /// "fine", "note" or "attention".
            let level: String
            let title: String
            let explanation: String
            let detail: String?
            let path: String?
        }
        struct Group: Encodable {
            let id: String
            let title: String
            let summary: String
            /// Why this group could not be read, for example a missing permission.
            let unavailable: String?
            let findings: [Finding]
        }

        let overall: String
        let needingACloserLook: Int
        let groups: [Group]
        let note: String
    }

    private func protection() -> ProtectionAnswer {
        let report = sources.protection()
        return ProtectionAnswer(
            overall: Self.name(of: report.overallLevel),
            needingACloserLook: report.count(of: .attention),
            groups: report.sections.map { section in
                ProtectionAnswer.Group(
                    id: section.id,
                    title: section.title,
                    summary: section.summary,
                    unavailable: section.unavailableReason,
                    findings: section.findings.map {
                        ProtectionAnswer.Finding(
                            level: Self.name(of: $0.level),
                            title: $0.title,
                            explanation: $0.explanation,
                            detail: $0.detail,
                            path: $0.fileURL?.path
                        )
                    }
                )
            },
            note: Self.readOnlyNote
        )
    }

    // MARK: - Apps

    private struct AppsAnswer: Encodable {
        struct App: Encodable {
            let name: String
            let identifier: String?
            let version: String?
            let path: String
            let sizeBytes: Int64
            let size: String
            /// When the app was last opened, where macOS has a record of it.
            let lastOpened: Date?
            let partOfMacOS: Bool
        }

        let appCount: Int
        let totalBytes: Int64
        let total: String
        /// The largest apps, up to the limit asked for.
        let apps: [App]
    }

    private func apps(limit: Int) -> AppsAnswer {
        let all = sources.apps().sorted { $0.sizeBytes > $1.sizeBytes }
        let total = all.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return AppsAnswer(
            appCount: all.count,
            totalBytes: total,
            total: Self.readable(total),
            apps: all.prefix(limit).map {
                AppsAnswer.App(
                    name: $0.app.name,
                    identifier: $0.app.bundleIdentifier,
                    version: $0.app.version,
                    path: $0.app.url.path,
                    sizeBytes: $0.sizeBytes,
                    size: Self.readable($0.sizeBytes),
                    lastOpened: $0.lastUsed,
                    partOfMacOS: $0.isPartOfMacOS
                )
            }
        )
    }

    // MARK: - History

    private struct HistoryAnswer: Encodable {
        struct Item: Encodable {
            let path: String
            let sizeBytes: Int64
            /// "held" (can still be put back), "restored" or "deleted".
            let state: String
        }
        struct Change: Encodable {
            let date: Date
            let title: String
            let explanation: String
            let canBePutBack: Bool
            let items: [Item]
        }

        let holdingAreaBytes: Int64
        let holdingArea: String
        /// Newest first.
        let changes: [Change]
        let note: String
    }

    private func history() -> Reply {
        let records: [ActionRecord]
        do {
            records = try ActionLog(fileURL: dataDirectory.appendingPathComponent("action-log.json")).load()
        } catch {
            return Reply(output: error.localizedDescription, exitCode: 1)
        }
        let held = records.reduce(Int64(0)) { $0 + $1.heldBytes }
        return json(HistoryAnswer(
            holdingAreaBytes: held,
            holdingArea: Self.readable(held),
            changes: records.reversed().map { record in
                HistoryAnswer.Change(
                    date: record.date,
                    title: record.title,
                    explanation: record.explanation,
                    canBePutBack: record.canUndo,
                    items: record.items.map {
                        HistoryAnswer.Item(path: $0.held.originalPath, sizeBytes: $0.held.sizeBytes, state: $0.state.rawValue)
                    }
                )
            },
            note: tr("Putting things back and deleting them for good is done in SiivOS, under History.")
        ))
    }
}

extension PerformanceSample {
    /// A reading that knows nothing, for when none could be taken.
    static func unknown(at date: Date) -> PerformanceSample {
        PerformanceSample(
            date: date,
            cpuUsedFraction: nil,
            coreCount: 1,
            memory: nil,
            topByCPU: [],
            topByMemory: [],
            battery: nil,
            thermal: .normal,
            isLowPowerMode: false,
            diskTotalBytes: nil,
            diskAvailableBytes: nil,
            uptimeSeconds: 0
        )
    }
}
