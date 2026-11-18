import Foundation
import SiivOSCore
import SwiftUI

/// Connects the Health Timeline to the readings kept on this Mac.
@MainActor
final class TimelineModel: ObservableObject {
    /// The one model the window and the menu bar share, so both show the same score.
    static let shared = TimelineModel()

    /// Readings and changes so far, as saved on this Mac.
    @Published private(set) var history: HealthHistory
    /// The latest score with its reasons, or `nil` until this Mac has been looked at
    /// since SiivOS was opened. Only the number is saved, not the reasons.
    @Published private(set) var score: HealthScore?
    /// True while SiivOS is looking at the Mac.
    @Published private(set) var isUpdating = false
    /// What SiivOS itself has changed, newest first, to show among the other changes.
    @Published private(set) var ownActions: [ActionRecord] = []
    /// A problem to show the user.
    @Published var message: String?
    /// When the Health Timeline was last looked at. Changes noticed after this are new.
    @Published private(set) var lastSeen: Date?

    /// How old the last reading must be before SiivOS takes a new one by itself.
    static let automaticInterval: TimeInterval = 6 * 3_600

    private let store: HealthStore
    private static let lastSeenKey = "healthTimelineLastSeen"

    init() {
        let store = HealthStore.standard()
        self.store = store
        history = store.load()
        let seen = UserDefaults.standard.double(forKey: Self.lastSeenKey)
        lastSeen = seen > 0 ? Date(timeIntervalSince1970: seen) : nil
    }

    /// Changes worth a second glance that were noticed since the Health Timeline was
    /// last looked at, newest first. The menu bar points these out.
    var unseenNoteworthy: [HealthEvent] {
        history.noteworthyEvents(after: lastSeen)
    }

    /// Called when the Health Timeline is shown and when it is left: everything in it
    /// has now been seen.
    func markSeen() {
        let now = Date()
        lastSeen = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastSeenKey)
    }

    /// The latest score as a number, from this session or from the last saved reading.
    var latestTotal: Int? {
        score?.total ?? history.readings.last?.score
    }

    /// The health score at each reading, oldest first, for the chart.
    var scorePoints: [TrendChart.Point] {
        history.readings.map { TrendChart.Point(date: $0.date, value: Double($0.score)) }
    }

    /// Free space in bytes at each reading that has it, oldest first, for the chart.
    var freeSpacePoints: [TrendChart.Point] {
        history.readings.compactMap { reading in
            guard let available = reading.diskAvailableBytes else {
                return nil
            }
            return TrendChart.Point(date: reading.date, value: Double(available))
        }
    }

    /// The size of the startup disk at the last reading.
    var diskTotalBytes: Int64? {
        history.readings.last?.diskTotalBytes
    }

    /// Takes a reading when the app opens, unless there is a recent one.
    func updateIfDue() {
        if let last = history.readings.last, Date().timeIntervalSince(last.date) < Self.automaticInterval {
            return
        }
        update()
    }

    /// Called when the Health Timeline is shown: makes sure there is a score with its
    /// reasons, and brings SiivOS's own changes up to date.
    func prepareForDisplay() {
        reloadOwnActions()
        if score == nil {
            update()
        }
    }

    /// Looks at the Mac and adds a reading. Only reads the Mac; the one thing written is
    /// SiivOS's own history file.
    func update() {
        guard !isUpdating else { return }
        isUpdating = true
        let store = self.store

        Task {
            let outcome = await Task.detached(priority: .utility) { () -> (HealthScore, HealthHistory?, String?) in
                let observation = HealthObservation.gather()
                do {
                    let updated = try store.record(observation)
                    return (observation.score, updated, nil)
                } catch {
                    return (observation.score, nil, error.localizedDescription)
                }
            }.value
            self.score = outcome.0
            if let updated = outcome.1 {
                self.history = updated
            }
            if let problem = outcome.2 {
                self.message = tr("The reading could not be saved: %1$@", problem)
            }
            self.isUpdating = false
        }
    }

    private func reloadOwnActions() {
        guard case .success(let core) = AppCore.shared, let records = try? core.history() else {
            return
        }
        ownActions = records
    }
}
