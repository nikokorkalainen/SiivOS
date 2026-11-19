import Foundation

/// A record of the last time SiivOS emptied the holding area by itself, so that the
/// user is told afterwards what was deleted and why.
public struct AutomaticEmptying: Codable, Equatable, Sendable {
    public let date: Date
    public let itemCount: Int
    public let bytes: Int64
    /// The waiting time the user had chosen, in days.
    public let afterDays: Int

    public init(date: Date, itemCount: Int, bytes: Int64, afterDays: Int) {
        self.date = date
        self.itemCount = itemCount
        self.bytes = bytes
        self.afterDays = afterDays
    }
}

/// The choices people can make about the holding area.
public struct HoldingAreaSettings: Codable, Equatable, Sendable {
    /// After how many days of waiting an item is deleted for good. Zero means never,
    /// which is what SiivOS starts with: nothing is ever deleted unless the user
    /// chooses a time here.
    public var deleteAfterDays: Int
    /// The size of the holding area, in bytes, past which SiivOS points it out. Zero
    /// means never.
    public var warnAboveBytes: Int64
    /// The last emptying SiivOS did by itself that the user has not yet been told about.
    public var lastEmptying: AutomaticEmptying?

    /// The waiting times offered in Settings, in days. Zero is "never".
    public static let deleteAfterChoices = [0, 30, 90, 365]
    /// The sizes offered in Settings, in bytes. Zero is "never".
    public static let warnAboveChoices: [Int64] = [0, 1_000_000_000, 5_000_000_000, 10_000_000_000, 25_000_000_000, 50_000_000_000]

    /// The settings SiivOS starts with: never delete, and point the holding area out
    /// once it holds more than 10 GB.
    public init() {
        deleteAfterDays = 0
        warnAboveBytes = 10_000_000_000
        lastEmptying = nil
    }

    /// Reads saved settings. Anything missing or not among the choices falls back to
    /// what SiivOS starts with; for deleting, that is never.
    public init(from decoder: Decoder) throws {
        let standard = HoldingAreaSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let days = try container.decodeIfPresent(Int.self, forKey: .deleteAfterDays) ?? standard.deleteAfterDays
        let bytes = try container.decodeIfPresent(Int64.self, forKey: .warnAboveBytes) ?? standard.warnAboveBytes
        deleteAfterDays = Self.deleteAfterChoices.contains(days) ? days : standard.deleteAfterDays
        warnAboveBytes = Self.warnAboveChoices.contains(bytes) ? bytes : standard.warnAboveBytes
        lastEmptying = try container.decodeIfPresent(AutomaticEmptying.self, forKey: .lastEmptying)
    }

    /// True when the holding area has grown past the size the user chose to be told about.
    public func isWorthPointingOut(heldBytes: Int64) -> Bool {
        warnAboveBytes > 0 && heldBytes > warnAboveBytes
    }
}

/// Keeps the holding area settings in a small readable file in SiivOS's own folder.
public struct HoldingAreaSettingsStore: Sendable {
    public let fileURL: URL

    public init(dataDirectory: URL) {
        fileURL = dataDirectory.appendingPathComponent("holding-area-settings.json")
    }

    public static func standard() -> HoldingAreaSettingsStore {
        HoldingAreaSettingsStore(dataDirectory: SiivOSData.standardDirectory())
    }

    /// The saved settings. A missing or unreadable file gives what SiivOS starts with,
    /// which never deletes anything.
    public func load() -> HoldingAreaSettings {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? decoder.decode(HoldingAreaSettings.self, from: data)
        else {
            return HoldingAreaSettings()
        }
        return settings
    }

    public func save(_ settings: HoldingAreaSettings) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}

/// Empties the holding area of what has waited longer than the user chose.
///
/// This is the one place where SiivOS deletes anything without asking at that moment.
/// It only ever happens because the user chose a waiting time in Settings, where what
/// it does is explained first. It deletes only items already removed by the user and
/// waiting in the holding area, and it leaves a record of what it deleted.
public enum HoldingAreaKeeper {
    /// Deletes for good what has waited longer than the chosen time, if a time was chosen.
    ///
    /// - Returns: What was deleted, or `nil` when no time is chosen or nothing was due.
    @discardableResult
    public static func emptyIfDue(
        core: SafetyCore,
        store: HoldingAreaSettingsStore,
        now: Date = Date()
    ) throws -> AutomaticEmptying? {
        var settings = store.load()
        let days = settings.deleteAfterDays
        guard days > 0, HoldingAreaSettings.deleteAfterChoices.contains(days) else {
            return nil
        }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let result = try core.deleteHeldItems(removedBefore: cutoff)
        guard result.itemCount > 0 else {
            return nil
        }
        // Whole seconds, so that the date survives being saved and read back unchanged.
        var emptying = AutomaticEmptying(
            date: Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down)),
            itemCount: result.itemCount,
            bytes: result.bytes,
            afterDays: days
        )
        // If the user has not seen the note about an earlier emptying yet, add to it.
        if let earlier = settings.lastEmptying {
            emptying = AutomaticEmptying(
                date: emptying.date,
                itemCount: emptying.itemCount + earlier.itemCount,
                bytes: emptying.bytes + earlier.bytes,
                afterDays: days
            )
        }
        settings.lastEmptying = emptying
        try store.save(settings)
        return emptying
    }
}
