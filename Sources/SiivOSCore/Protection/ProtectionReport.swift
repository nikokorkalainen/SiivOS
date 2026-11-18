import Foundation

/// One thing the protection check looked at, with what SiivOS makes of it.
public struct ProtectionFinding: Equatable, Identifiable, Sendable {
    public enum Level: Int, Sendable {
        /// Nothing unusual.
        case fine
        /// Worth a look, but often perfectly normal.
        case note
        /// Unusual enough that the user should decide what to do about it.
        case attention
    }

    public let id: String
    public let level: Level
    /// The name of the thing: a setting, a background item, an extension, a profile.
    public let title: String
    /// What it is and why it has this level, in plain words.
    public let explanation: String
    /// A path, identifier or other small print, when it helps to tell items apart.
    public let detail: String?
    /// The file to show in Finder, if there is one.
    public let fileURL: URL?
    /// True when SiivOS can move the file to the holding area on request.
    public let canRemove: Bool

    public init(
        id: String,
        level: Level,
        title: String,
        explanation: String,
        detail: String? = nil,
        fileURL: URL? = nil,
        canRemove: Bool = false
    ) {
        self.id = id
        self.level = level
        self.title = title
        self.explanation = explanation
        self.detail = detail
        self.fileURL = fileURL
        self.canRemove = canRemove
    }
}

/// What one kind of protection check found.
public struct ProtectionSection: Equatable, Identifiable, Sendable {
    /// Stable identifier, for example "background-items".
    public let id: String
    public let title: String
    /// One or two sentences on what this check looks at.
    public let summary: String
    /// Everything that was looked at, most noteworthy first.
    public let findings: [ProtectionFinding]
    /// Why the check could not look, for example a missing permission.
    public let unavailableReason: String?

    public init(id: String, title: String, summary: String, findings: [ProtectionFinding], unavailableReason: String? = nil) {
        self.id = id
        self.title = title
        self.summary = summary
        self.findings = findings.enumerated()
            .sorted { first, second in
                if first.element.level != second.element.level {
                    return first.element.level.rawValue > second.element.level.rawValue
                }
                return first.offset < second.offset
            }
            .map { $0.element }
        self.unavailableReason = unavailableReason
    }

    /// The findings that deserve the user's eye: notes and attention.
    public var noteworthy: [ProtectionFinding] {
        findings.filter { $0.level != .fine }
    }

    /// The findings with nothing unusual about them.
    public var unremarkable: [ProtectionFinding] {
        findings.filter { $0.level == .fine }
    }
}

/// The combined results of a protection check.
public struct ProtectionReport: Equatable, Sendable {
    public let sections: [ProtectionSection]

    public init(sections: [ProtectionSection]) {
        self.sections = sections
    }

    public func count(of level: ProtectionFinding.Level) -> Int {
        sections.reduce(0) { $0 + $1.findings.filter { $0.level == level }.count }
    }

    /// The highest level among all findings.
    public var overallLevel: ProtectionFinding.Level {
        if count(of: .attention) > 0 { return .attention }
        if count(of: .note) > 0 { return .note }
        return .fine
    }
}
