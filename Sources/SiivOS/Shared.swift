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

    func refresh() {
        guard case .success(let core) = AppCore.shared, let records = try? core.history() else {
            return
        }
        heldBytes = records.reduce(0) { $0 + $1.heldBytes }
    }
}

/// A file size written out for people, for example "1,2 GB".
func formatBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
}

/// Turns a list of failures into one message, or `nil` when there were none.
func describe(_ failures: [ChangeResult.Failure], intro: String) -> String? {
    guard !failures.isEmpty else { return nil }
    let lines = failures.map { "\($0.path): \($0.message)" }
    return ([intro] + lines).joined(separator: "\n")
}
