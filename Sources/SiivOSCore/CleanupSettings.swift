import Foundation

/// The choices people can make about what Cleanup looks for.
///
/// Kept short on purpose: a setting is only here because people reasonably want
/// different behaviour. None of them makes Cleanup less careful; they only narrow what
/// it lists.
public struct CleanupSettings: Codable, Equatable, Sendable {
    /// How many days a download must have been left untouched to count as old.
    public var oldDownloadDays: Int
    /// How big a file must be to count as large, in bytes.
    public var largeFileBytes: Int64
    /// Identifiers of the checks that are turned off, for example "duplicates".
    public var checksTurnedOff: [String]
    /// Folders whose contents Cleanup never lists, as full paths.
    public var foldersLeftOut: [String]

    /// The ages offered in Settings, in days.
    public static let oldDownloadChoices = [30, 60, 90, 180, 365]
    /// The sizes offered in Settings, in bytes.
    public static let largeFileChoices: [Int64] = [50_000_000, 100_000_000, 250_000_000, 500_000_000, 1_000_000_000]

    /// The settings SiivOS starts with.
    public init() {
        oldDownloadDays = 90
        largeFileBytes = 100_000_000
        checksTurnedOff = []
        foldersLeftOut = []
    }

    /// Reads settings saved by this or another version of SiivOS. Anything missing or
    /// not among the choices falls back to what SiivOS starts with.
    public init(from decoder: Decoder) throws {
        let standard = CleanupSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let days = try container.decodeIfPresent(Int.self, forKey: .oldDownloadDays) ?? standard.oldDownloadDays
        let bytes = try container.decodeIfPresent(Int64.self, forKey: .largeFileBytes) ?? standard.largeFileBytes
        oldDownloadDays = Self.oldDownloadChoices.contains(days) ? days : standard.oldDownloadDays
        largeFileBytes = Self.largeFileChoices.contains(bytes) ? bytes : standard.largeFileBytes
        checksTurnedOff = try container.decodeIfPresent([String].self, forKey: .checksTurnedOff) ?? []
        foldersLeftOut = try container.decodeIfPresent([String].self, forKey: .foldersLeftOut) ?? []
    }

    /// The folders left out, as file URLs.
    public var folderURLsLeftOut: [URL] {
        foldersLeftOut.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// True when nothing has been changed from what SiivOS starts with.
    public var isStandard: Bool {
        self == CleanupSettings()
    }
}

/// Keeps the Cleanup settings in a small readable file in SiivOS's own folder, where
/// both the app and the tool for AI agents can read them, so both scan the same way.
public struct CleanupSettingsStore: Sendable {
    public let fileURL: URL

    public init(dataDirectory: URL) {
        fileURL = dataDirectory.appendingPathComponent("cleanup-settings.json")
    }

    public static func standard() -> CleanupSettingsStore {
        CleanupSettingsStore(dataDirectory: SiivOSData.standardDirectory())
    }

    /// The saved settings. A missing or unreadable file gives what SiivOS starts with.
    public func load() -> CleanupSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(CleanupSettings.self, from: data)
        else {
            return CleanupSettings()
        }
        return settings
    }

    public func save(_ settings: CleanupSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
