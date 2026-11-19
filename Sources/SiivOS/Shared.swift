import Foundation
import SiivOSCore
import SwiftUI

/// The one safety core every screen uses, so that all changes go through the same place.
enum AppCore {
    static let shared: Result<SafetyCore, Error> = Result(catching: { try SafetyCore.standard() })
}

/// How much is waiting in the holding area, for the sidebar. Screens call `refresh()`
/// after they change anything.
@MainActor
final class HoldingStatus: ObservableObject {
    static let shared = HoldingStatus()

    @Published private(set) var heldBytes: Int64 = 0
    /// The user's choices about the holding area, and the note about the last time
    /// SiivOS emptied it by itself, if the user has not seen that yet.
    @Published private(set) var settings = HoldingAreaSettingsStore.standard().load()

    /// True when the holding area has grown past the size the user chose to be told about.
    var isWorthPointingOut: Bool {
        settings.isWorthPointingOut(heldBytes: heldBytes)
    }

    func refresh() {
        settings = HoldingAreaSettingsStore.standard().load()
        guard case .success(let core) = AppCore.shared, let records = try? core.history() else {
            return
        }
        heldBytes = records.reduce(0) { $0 + $1.heldBytes }
    }

    /// Deletes for good what has waited in the holding area longer than the user chose
    /// in Settings. Does nothing when no time is chosen, which is how SiivOS starts.
    func emptyIfDue() {
        guard case .success(let core) = AppCore.shared else {
            return
        }
        Task {
            _ = await Task.detached(priority: .utility) {
                try? HoldingAreaKeeper.emptyIfDue(core: core, store: HoldingAreaSettingsStore.standard())
            }.value
            self.refresh()
        }
    }

    /// Hides the note about the last automatic emptying, once the user has read it.
    func dismissEmptyingNote() {
        let store = HoldingAreaSettingsStore.standard()
        var current = store.load()
        current.lastEmptying = nil
        try? store.save(current)
        refresh()
    }
}

/// A file size written out for people, for example "1,2 GB".
func formatBytes(_ value: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    // "0 KB", not "Zero KB".
    formatter.allowsNonnumericFormatting = false
    return formatter.string(fromByteCount: value)
}

/// Turns a list of failures into one message, or `nil` when there were none.
func describe(_ failures: [ChangeResult.Failure], intro: String) -> String? {
    guard !failures.isEmpty else { return nil }
    let lines = failures.map { "\($0.path): \($0.message)" }
    return ([intro] + lines).joined(separator: "\n")
}
