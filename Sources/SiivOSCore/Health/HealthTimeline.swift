import Foundation

/// What is on the Mac at one moment, as far as the timeline keeps track of it.
public struct HealthInventory: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        /// What identifies the thing from one reading to the next.
        public let key: String
        /// Its name, as shown to people.
        public let name: String
        /// Something more about it: an app's version, an extension's browser.
        public let detail: String?

        public init(key: String, name: String, detail: String? = nil) {
            self.key = key
            self.name = name
            self.detail = detail
        }
    }

    public var apps: [Entry]
    public var backgroundItems: [Entry]
    public var extensions: [Entry]
    public var profiles: [Entry]
    /// Identifiers of macOS's own protections that are switched off.
    public var protectionsOff: [String]

    public init(apps: [Entry], backgroundItems: [Entry], extensions: [Entry], profiles: [Entry], protectionsOff: [String]) {
        self.apps = apps
        self.backgroundItems = backgroundItems
        self.extensions = extensions
        self.profiles = profiles
        self.protectionsOff = protectionsOff
    }
}

/// The health score and free space at one moment.
public struct HealthReading: Codable, Equatable, Identifiable, Sendable {
    public let date: Date
    public let score: Int
    public let diskTotalBytes: Int64?
    public let diskAvailableBytes: Int64?

    public var id: Date { date }
}

/// Something that changed on the Mac between two readings.
public struct HealthEvent: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case trackingStarted
        case appAdded
        case appRemoved
        case appUpdated
        case backgroundItemAdded
        case backgroundItemRemoved
        case extensionAdded
        case extensionRemoved
        case profileAdded
        case profileRemoved
        case protectionTurnedOff
        case protectionTurnedOn
        case freeSpaceWentDown
        case freeSpaceWentUp
    }

    public let id: UUID
    /// When SiivOS noticed the change. The change itself happened some time before,
    /// since the reading before this one.
    public let date: Date
    public let kind: Kind
    /// The name of the thing that changed, or the identifier of a protection.
    public let subject: String
    /// Something more: versions for an update, the browser for an extension.
    public let detail: String?
    /// For free-space changes, by how much.
    public let amountBytes: Int64?

    public init(id: UUID = UUID(), date: Date, kind: Kind, subject: String = "", detail: String? = nil, amountBytes: Int64? = nil) {
        self.id = id
        self.date = date
        self.kind = kind
        self.subject = subject
        self.detail = detail
        self.amountBytes = amountBytes
    }

    /// True for changes worth a second glance: something new that starts by itself,
    /// a new profile, or a protection that was turned off.
    public var isNoteworthy: Bool {
        switch kind {
        case .backgroundItemAdded, .profileAdded, .protectionTurnedOff:
            return true
        default:
            return false
        }
    }

    /// What happened, in the language the app is shown in. Worked out when shown, not
    /// stored, so the history reads right after a change of language.
    public var title: String {
        switch kind {
        case .trackingStarted: return tr("SiivOS started keeping track of this Mac")
        case .appAdded: return tr("%1$@ was installed", subject)
        case .appRemoved: return tr("%1$@ was removed", subject)
        case .appUpdated: return tr("%1$@ was updated", subject)
        case .backgroundItemAdded: return tr("New background item: %1$@", subject)
        case .backgroundItemRemoved: return tr("Background item gone: %1$@", subject)
        case .extensionAdded: return tr("Browser extension added: %1$@", subject)
        case .extensionRemoved: return tr("Browser extension removed: %1$@", subject)
        case .profileAdded: return tr("Configuration profile installed: %1$@", subject)
        case .profileRemoved: return tr("Configuration profile removed: %1$@", subject)
        case .protectionTurnedOff: return tr("%1$@ was turned off", HealthScoring.protectionName(subject))
        case .protectionTurnedOn: return tr("%1$@ was turned on", HealthScoring.protectionName(subject))
        case .freeSpaceWentDown: return tr("Free space went down by %1$@", formattedAmount)
        case .freeSpaceWentUp: return tr("Free space went up by %1$@", formattedAmount)
        }
    }

    /// A second line for the changes that need one.
    public var explanation: String? {
        switch kind {
        case .backgroundItemAdded:
            return tr("It starts by itself from now on. If you do not recognise it, look at it in Protection.")
        case .profileAdded:
            return tr("A profile can change settings on this Mac. If you do not recognise it, look at it in Protection.")
        case .protectionTurnedOff:
            return tr("Unless you did this on purpose, look at it in Protection.")
        default:
            return detail
        }
    }

    private var formattedAmount: String {
        ByteCountFormatter.string(fromByteCount: amountBytes ?? 0, countStyle: .file)
    }
}

/// Everything the timeline remembers.
public struct HealthHistory: Codable, Equatable, Sendable {
    /// Readings, oldest first.
    public var readings: [HealthReading]
    /// Changes, oldest first.
    public var events: [HealthEvent]
    /// What was on the Mac at the last reading, to compare the next one with.
    public var inventory: HealthInventory?

    public init(readings: [HealthReading] = [], events: [HealthEvent] = [], inventory: HealthInventory? = nil) {
        self.readings = readings
        self.events = events
        self.inventory = inventory
    }
}

/// One look at the Mac: what is on it and how it is doing.
public struct HealthObservation: Equatable, Sendable {
    public let inventory: HealthInventory
    public let diskTotalBytes: Int64?
    public let diskAvailableBytes: Int64?
    public let memoryPressure: MemoryUsage.Pressure?
    public let batteryHealthPercent: Int?
    /// How many things the protection check marked as needing a closer look.
    public let attentionCount: Int

    public init(
        inventory: HealthInventory,
        diskTotalBytes: Int64?,
        diskAvailableBytes: Int64?,
        memoryPressure: MemoryUsage.Pressure?,
        batteryHealthPercent: Int?,
        attentionCount: Int
    ) {
        self.inventory = inventory
        self.diskTotalBytes = diskTotalBytes
        self.diskAvailableBytes = diskAvailableBytes
        self.memoryPressure = memoryPressure
        self.batteryHealthPercent = batteryHealthPercent
        self.attentionCount = attentionCount
    }

    public var score: HealthScore {
        var freeFraction: Double?
        if let total = diskTotalBytes, total > 0, let available = diskAvailableBytes {
            freeFraction = min(1, max(0, Double(available) / Double(total)))
        }
        return HealthScoring.score(
            for: HealthFacts(
                diskFreeFraction: freeFraction,
                memoryPressure: memoryPressure,
                protectionsOff: inventory.protectionsOff,
                attentionCount: attentionCount,
                batteryHealthPercent: batteryHealthPercent
            )
        )
    }
}

/// Turns observations into history: readings over time, and what changed in between.
public enum HealthTimeline {
    /// A new reading replaces the last one when they are this close together, so opening
    /// the app several times in an hour does not fill the history.
    static let minimumSpacing: TimeInterval = 3_600
    /// Free space must change by at least this much, or by two percent of the disk if
    /// that is more, to be worth an entry.
    static let minimumSpaceChange: Int64 = 5_000_000_000
    static let maximumEvents = 1_000
    static let maximumReadings = 2_000

    /// Adds an observation to the history and returns the result. Changes nothing on disk.
    public static func record(_ observation: HealthObservation, into history: HealthHistory, now: Date = Date()) -> HealthHistory {
        // Whole seconds, so that a date survives being saved and read back unchanged.
        let date = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        var updated = history
        var newEvents: [HealthEvent] = []

        if let earlier = history.inventory {
            newEvents += changes(from: earlier, to: observation.inventory, date: date)
        } else {
            newEvents.append(HealthEvent(date: date, kind: .trackingStarted))
        }

        if let last = history.readings.last,
           let before = last.diskAvailableBytes,
           let after = observation.diskAvailableBytes {
            let threshold = max(minimumSpaceChange, (observation.diskTotalBytes ?? 0) / 50)
            let change = after - before
            if change <= -threshold {
                newEvents.append(HealthEvent(date: date, kind: .freeSpaceWentDown, amountBytes: -change))
            } else if change >= threshold {
                newEvents.append(HealthEvent(date: date, kind: .freeSpaceWentUp, amountBytes: change))
            }
        }

        let reading = HealthReading(
            date: date,
            score: observation.score.total,
            diskTotalBytes: observation.diskTotalBytes,
            diskAvailableBytes: observation.diskAvailableBytes
        )
        // Keep the earlier reading as the point of comparison when the new one comes soon
        // after and nothing changed in between; otherwise slow changes would never add up.
        if let last = updated.readings.last, date.timeIntervalSince(last.date) < minimumSpacing, newEvents.isEmpty {
            updated.readings[updated.readings.count - 1] = HealthReading(
                date: last.date,
                score: reading.score,
                diskTotalBytes: last.diskTotalBytes,
                diskAvailableBytes: last.diskAvailableBytes
            )
        } else {
            updated.readings.append(reading)
        }

        updated.events += newEvents
        updated.inventory = observation.inventory
        updated.readings = Array(updated.readings.suffix(maximumReadings))
        updated.events = Array(updated.events.suffix(maximumEvents))
        return updated
    }

    /// What is different between two inventories.
    static func changes(from earlier: HealthInventory, to later: HealthInventory, date: Date) -> [HealthEvent] {
        var events: [HealthEvent] = []

        let earlierApps = Dictionary(earlier.apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let laterApps = Dictionary(later.apps.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        for app in later.apps {
            guard let before = earlierApps[app.key] else {
                events.append(HealthEvent(date: date, kind: .appAdded, subject: app.name, detail: app.detail))
                continue
            }
            if let old = before.detail, let new = app.detail, old != new {
                events.append(HealthEvent(date: date, kind: .appUpdated, subject: app.name, detail: "\(old) → \(new)"))
            }
        }
        for app in earlier.apps where laterApps[app.key] == nil {
            events.append(HealthEvent(date: date, kind: .appRemoved, subject: app.name))
        }

        events += addedAndRemoved(earlier.backgroundItems, later.backgroundItems, .backgroundItemAdded, .backgroundItemRemoved, date)
        events += addedAndRemoved(earlier.extensions, later.extensions, .extensionAdded, .extensionRemoved, date)
        events += addedAndRemoved(earlier.profiles, later.profiles, .profileAdded, .profileRemoved, date)

        for identifier in later.protectionsOff where !earlier.protectionsOff.contains(identifier) {
            events.append(HealthEvent(date: date, kind: .protectionTurnedOff, subject: identifier))
        }
        for identifier in earlier.protectionsOff where !later.protectionsOff.contains(identifier) {
            events.append(HealthEvent(date: date, kind: .protectionTurnedOn, subject: identifier))
        }
        return events
    }

    private static func addedAndRemoved(
        _ earlier: [HealthInventory.Entry],
        _ later: [HealthInventory.Entry],
        _ added: HealthEvent.Kind,
        _ removed: HealthEvent.Kind,
        _ date: Date
    ) -> [HealthEvent] {
        let earlierKeys = Set(earlier.map { $0.key })
        let laterKeys = Set(later.map { $0.key })
        var events: [HealthEvent] = []
        for entry in later where !earlierKeys.contains(entry.key) {
            events.append(HealthEvent(date: date, kind: added, subject: entry.name, detail: entry.detail))
        }
        for entry in earlier where !laterKeys.contains(entry.key) {
            events.append(HealthEvent(date: date, kind: removed, subject: entry.name, detail: entry.detail))
        }
        return events
    }
}

/// Keeps the health history in a readable JSON file on this Mac, and nowhere else.
public final class HealthStore: @unchecked Sendable {
    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The store the app uses: `~/Library/Application Support/SiivOS/health-history.json`.
    public static func standard() -> HealthStore {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return HealthStore(fileURL: support.appendingPathComponent("SiivOS/health-history.json"))
    }

    /// The history so far. A missing or unreadable file gives an empty history: losing
    /// the timeline is a pity, but unlike the action log nothing depends on it.
    public func load() -> HealthHistory {
        lock.lock()
        defer { lock.unlock() }
        return read()
    }

    /// Adds an observation to the history, saves it, and returns the new history.
    public func record(_ observation: HealthObservation, now: Date = Date()) throws -> HealthHistory {
        lock.lock()
        defer { lock.unlock() }
        let updated = HealthTimeline.record(observation, into: read(), now: now)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(updated)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return updated
    }

    private func read() -> HealthHistory {
        guard let data = try? Data(contentsOf: fileURL) else {
            return HealthHistory()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(HealthHistory.self, from: data)) ?? HealthHistory()
    }
}

extension HealthObservation {
    /// Looks at this Mac and gathers an observation. Only reads; never changes anything.
    /// It runs the protection check, so it takes a few seconds.
    public static func gather(homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory())) -> HealthObservation {
        let report = ProtectionCheck.run(homeDirectory: homeDirectory)
        let apps = InstalledApps.find(in: InstalledApps.standardDirectories(homeDirectory: homeDirectory))
        let sample = PerformanceSampler().sample()
        return from(report: report, apps: apps, sample: sample)
    }

    /// Builds an observation from the results of the checks SiivOS already has.
    static func from(report: ProtectionReport, apps: [InstalledApp], sample: PerformanceSample) -> HealthObservation {
        func entries(_ sectionID: String) -> [HealthInventory.Entry] {
            let findings = report.sections.first { $0.id == sectionID }?.findings ?? []
            return findings.map { HealthInventory.Entry(key: $0.id, name: $0.title, detail: $0.detail) }
        }
        let builtIn = report.sections.first { $0.id == "macos" }?.findings ?? []
        // Attention within macOS's own protections is counted there, not twice.
        let attention = report.sections
            .filter { $0.id != "macos" }
            .reduce(0) { $0 + $1.findings.filter { $0.level == .attention }.count }

        return HealthObservation(
            inventory: HealthInventory(
                apps: apps.map { app in
                    HealthInventory.Entry(key: app.bundleIdentifier ?? app.url.path, name: app.name, detail: app.version)
                },
                backgroundItems: entries("background-items"),
                extensions: entries("browser-extensions"),
                profiles: entries("profiles"),
                protectionsOff: builtIn.filter { $0.level != .fine }.map { $0.id }
            ),
            diskTotalBytes: sample.diskTotalBytes,
            diskAvailableBytes: sample.diskAvailableBytes,
            memoryPressure: sample.memory?.pressure,
            batteryHealthPercent: sample.battery?.healthPercent,
            attentionCount: attention
        )
    }
}
