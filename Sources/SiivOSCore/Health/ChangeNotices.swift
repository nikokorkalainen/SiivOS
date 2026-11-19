import Foundation

/// What SiivOS says in a notification about changes worth a second glance. Putting it
/// on screen is the app's job; this only works out the words.
public struct ChangeNotice: Equatable, Sendable {
    public let title: String
    public let body: String
    /// When the newest of the changes was noticed. Everything up to this moment has now
    /// been told about, and is left out the next time.
    public let coversUpTo: Date

    public init(title: String, body: String, coversUpTo: Date) {
        self.title = title
        self.body = body
        self.coversUpTo = coversUpTo
    }
}

public enum ChangeNotices {
    /// How many changes a notice names before it only says how many more there are.
    static let namedAtMost = 3

    /// The notice for the changes worth a second glance that were noticed after the
    /// given moment, or `nil` when there are none. One change is told in its own
    /// words; several are counted and the newest named.
    public static func notice(for history: HealthHistory, after date: Date) -> ChangeNotice? {
        let events = history.noteworthyEvents(after: date)
        guard let newest = events.first else {
            return nil
        }
        if events.count == 1 {
            return ChangeNotice(title: newest.title, body: newest.explanation ?? "", coversUpTo: newest.date)
        }
        var lines = events.prefix(namedAtMost).map { $0.title }
        if events.count > namedAtMost {
            lines.append(tr("And %1$@ more.", "\(events.count - namedAtMost)"))
        }
        return ChangeNotice(
            title: tr("%1$@ changes worth a look on this Mac", "\(events.count)"),
            body: lines.joined(separator: "\n"),
            coversUpTo: newest.date
        )
    }
}

extension HealthTimeline {
    /// True when one of the given background items was not on the Mac at the last
    /// reading. Listing background items is quick, so this is how SiivOS finds out
    /// between readings that a new one is worth taking. With no reading yet there is
    /// nothing to compare with, and the first reading is on its way anyway.
    public static func hasNewBackgroundItems(_ items: [BackgroundItem], since history: HealthHistory) -> Bool {
        guard let inventory = history.inventory else {
            return false
        }
        let known = Set(inventory.backgroundItems.map { $0.key })
        return items.contains { !known.contains($0.url.path) }
    }
}
