import Foundation
import SiivOSCore

/// The one safety core every screen uses, so that all changes go through the same place.
enum AppCore {
    static let shared: Result<SafetyCore, Error> = Result(catching: { try SafetyCore.standard() })
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
