import Foundation

/// A proposed removal: what would be moved, what would be left alone, and the
/// explanation to show the user first.
///
/// Only `SafetyCore.plan` can create one, and `SafetyCore.apply` accepts nothing else,
/// so no removal can run without an explanation having been prepared for it.
public struct RemovalPlan: Equatable, Identifiable, Sendable {
    public struct Item: Equatable, Identifiable, Sendable {
        public let url: URL
        public let sizeBytes: Int64
        /// True when the whole change is called off if this item cannot be moved.
        public let isRequired: Bool

        public var id: URL { url }
    }

    public struct Refusal: Equatable, Identifiable, Sendable {
        public let url: URL
        /// Plain-language reason the item will be left alone.
        public let reason: String

        public var id: URL { url }
    }

    public let id: UUID
    public let title: String
    public let explanation: String
    public let items: [Item]
    public let refused: [Refusal]

    /// Combined size of the items that would be moved, in bytes.
    public var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.sizeBytes }
    }
}

/// What happened when a change was made, put back or deleted for good.
public struct ChangeResult: Sendable {
    public struct Failure: Equatable, Sendable {
        public let path: String
        public let message: String
    }

    /// The record after the change.
    public let record: ActionRecord
    /// Items that could not be handled. They stay where they were.
    public let failures: [Failure]
}

public enum SafetyCoreError: LocalizedError {
    case nothingToRemove
    case recordNotFound

    public var errorDescription: String? {
        switch self {
        case .nothingToRemove:
            return tr("There is nothing to remove.")
        case .recordNotFound:
            return tr("That change is no longer in the SiivOS history.")
        }
    }
}

/// The only way SiivOS removes anything.
///
/// Removing means moving items to the holding area and writing down what was done,
/// so every change can be explained first and put back afterwards.
public final class SafetyCore: @unchecked Sendable {
    private let lock = NSLock()
    private let fileManager: FileManager
    private let holdingArea: HoldingArea
    private let log: ActionLog
    private let rules: SafetyRules

    /// Where the history of changes is stored.
    var logFileURL: URL { log.fileURL }

    /// - Parameters:
    ///   - baseDirectory: Folder for SiivOS's own data. Created if needed.
    ///   - homeDirectory: The user's home folder, used by the safety rules.
    public init(
        baseDirectory: URL,
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        fileManager: FileManager = .default
    ) throws {
        let holdingDirectory = baseDirectory.appendingPathComponent("HoldingArea", isDirectory: true)
        try fileManager.createDirectory(at: holdingDirectory, withIntermediateDirectories: true)

        self.fileManager = fileManager
        self.holdingArea = HoldingArea(directory: holdingDirectory, fileManager: fileManager)
        self.log = ActionLog(
            fileURL: baseDirectory.appendingPathComponent("action-log.json"),
            fileManager: fileManager
        )
        self.rules = SafetyRules(homeDirectory: homeDirectory, holdingDirectory: holdingDirectory)
    }

    /// The safety core the app uses, storing its data in `~/Library/Application Support/SiivOS`.
    public static func standard() throws -> SafetyCore {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return try SafetyCore(baseDirectory: support.appendingPathComponent("SiivOS", isDirectory: true))
    }

    // MARK: - Planning

    /// Works out what removing the given items would do. Changes nothing.
    ///
    /// - Parameters:
    ///   - urls: The files and folders someone wants removed.
    ///   - title: Short name for the change. Left out, one is made from the items.
    ///   - reason: One plain sentence to show first, when the change needs introducing
    ///     (for example what uninstalling an app takes with it). Left out, none is shown.
    ///   - required: Items among `urls` that the change makes no sense without, such as the
    ///     app itself when uninstalling. If one of them may not or cannot be moved, nothing is.
    public func plan(
        removing urls: [URL],
        title: String? = nil,
        reason: String = "",
        required: [URL] = []
    ) -> RemovalPlan {
        var seenPaths = Set<String>()
        var candidates: [URL] = []
        for url in urls {
            let standardized = url.standardizedFileURL
            if seenPaths.insert(standardized.path).inserted {
                candidates.append(standardized)
            }
        }

        var allowed: [URL] = []
        var refused: [RemovalPlan.Refusal] = []
        for url in candidates {
            if !exists(url) {
                refused.append(RemovalPlan.Refusal(url: url, reason: tr("It no longer exists.")))
            } else if let refusal = rules.reasonToRefuse(url) {
                refused.append(RemovalPlan.Refusal(url: url, reason: refusal))
            } else {
                allowed.append(url)
            }
        }

        let requiredPaths = Set(required.map { $0.standardizedFileURL.path })
        if !requiredPaths.isSubset(of: Set(allowed.map { $0.path })) {
            // A required item is missing or protected, so the rest is left alone too.
            allowed = []
        }

        // An item inside a folder that is also being removed moves along with that folder.
        let unordered = allowed
            .filter { url in
                !allowed.contains { other in url.path.hasPrefix(other.path + "/") }
            }
            .map { url in
                RemovalPlan.Item(
                    url: url,
                    sizeBytes: FileSize.onDisk(of: url, fileManager: fileManager),
                    isRequired: requiredPaths.contains(url.path)
                )
            }
        // Required items go first, so that nothing else has moved if one of them fails.
        let items = unordered.filter { $0.isRequired } + unordered.filter { !$0.isRequired }

        let totalBytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return RemovalPlan(
            id: UUID(),
            title: title ?? Self.defaultTitle(for: items),
            explanation: Self.explanation(itemCount: items.count, totalBytes: totalBytes, reason: reason),
            items: items,
            refused: refused
        )
    }

    private static func defaultTitle(for items: [RemovalPlan.Item]) -> String {
        if items.count == 1 {
            return tr("Removed %1$@", items[0].url.lastPathComponent)
        }
        return tr("Removed %1$@ items", "\(items.count)")
    }

    private static func explanation(itemCount: Int, totalBytes: Int64, reason: String) -> String {
        guard itemCount > 0 else {
            return tr("None of the chosen items can be removed, so nothing will change.")
        }
        let size = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        let whatHappens = itemCount == 1
            ? tr("SiivOS will move 1 item (%1$@) to the holding area. Nothing is deleted yet. The space is freed when you delete it permanently in History.", size)
            : tr("SiivOS will move %1$@ items (%2$@) to the holding area. Nothing is deleted yet. The space is freed when you delete them permanently in History.", "\(itemCount)", size)
        return reason.isEmpty ? whatHappens : reason + " " + whatHappens
    }

    // MARK: - Changing things

    /// Carries out a plan: moves its items to the holding area and records the change.
    ///
    /// Items that cannot be moved, for example because macOS protects them, are left
    /// where they are and listed in the result. If a required item cannot be moved, if
    /// nothing at all could be moved, or if the change could not be recorded, an error
    /// is thrown and nothing stays moved.
    public func apply(_ plan: RemovalPlan) throws -> ChangeResult {
        lock.lock()
        defer { lock.unlock() }

        guard !plan.items.isEmpty else {
            throw SafetyCoreError.nothingToRemove
        }
        // Read the history first, so a damaged history file stops the change before anything moves.
        var records = try log.load()

        var held: [HeldItem] = []
        var failures: [ChangeResult.Failure] = []
        var firstError: Error?
        for item in plan.items {
            do {
                held.append(try holdingArea.hold(item.url))
            } catch {
                if item.isRequired {
                    for moved in held.reversed() {
                        try? holdingArea.restore(moved)
                    }
                    throw error
                }
                failures.append(ChangeResult.Failure(path: item.url.path, message: error.localizedDescription))
                if firstError == nil {
                    firstError = error
                }
            }
        }
        guard !held.isEmpty else {
            throw firstError ?? SafetyCoreError.nothingToRemove
        }

        let record = ActionRecord(
            id: UUID(),
            date: Self.currentDate(),
            title: plan.title,
            explanation: plan.explanation,
            items: held.map { ActionRecord.Item(held: $0, state: .held) }
        )
        records.append(record)
        do {
            try log.save(records)
        } catch {
            // A change that is not written down could not be undone later, so put everything back.
            for item in held.reversed() {
                try? holdingArea.restore(item)
            }
            throw error
        }
        return ChangeResult(record: record, failures: failures)
    }

    /// Puts back every item of a recorded change that is still in the holding area.
    public func undo(recordID: UUID) throws -> ChangeResult {
        try update(recordID: recordID, to: .restored) { item in
            try holdingArea.restore(item)
        }
    }

    /// Deletes for good every item of a recorded change that is still in the holding area.
    /// This frees the disk space and cannot be undone.
    public func deletePermanently(recordID: UUID) throws -> ChangeResult {
        try update(recordID: recordID, to: .deleted) { item in
            try holdingArea.deletePermanently(item)
        }
    }

    private func update(
        recordID: UUID,
        to newState: ActionRecord.ItemState,
        using operation: (HeldItem) throws -> Void
    ) throws -> ChangeResult {
        lock.lock()
        defer { lock.unlock() }

        var records = try log.load()
        guard let recordIndex = records.firstIndex(where: { $0.id == recordID }) else {
            throw SafetyCoreError.recordNotFound
        }

        var updated = records[recordIndex]
        var failures: [ChangeResult.Failure] = []
        for itemIndex in updated.items.indices {
            guard updated.items[itemIndex].state == .held else {
                continue
            }
            let item = updated.items[itemIndex].held
            do {
                try operation(item)
                updated.items[itemIndex].state = newState
            } catch {
                failures.append(
                    ChangeResult.Failure(path: item.originalPath, message: error.localizedDescription)
                )
            }
        }

        records[recordIndex] = updated
        try log.save(records)
        return ChangeResult(record: updated, failures: failures)
    }

    // MARK: - Reading

    /// Every change SiivOS has made, newest first.
    public func history() throws -> [ActionRecord] {
        lock.lock()
        defer { lock.unlock() }
        let records = try log.load()
        return Array(records.reversed())
    }

    // MARK: - Helpers

    /// The current time, rounded down to a whole second so it survives being saved and read back unchanged.
    private static func currentDate() -> Date {
        Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
    }

    /// True when something exists at the URL. A link counts even if its target is gone.
    private func exists(_ url: URL) -> Bool {
        (try? fileManager.attributesOfItem(atPath: url.path)) != nil
    }
}
