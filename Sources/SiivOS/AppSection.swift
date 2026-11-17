import Foundation
import SiivOSCore

/// The areas of the app shown in the sidebar.
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case cleanup
    case apps
    case performance
    case protection
    case timeline
    case history

    var id: AppSection { self }

    var title: String {
        switch self {
        case .overview: return tr("Overview")
        case .cleanup: return tr("Cleanup")
        case .apps: return tr("Apps")
        case .performance: return tr("Performance")
        case .protection: return tr("Protection")
        case .timeline: return tr("Health Timeline")
        case .history: return tr("History")
        }
    }

    /// Name of the SF Symbol shown next to the title.
    var symbol: String {
        switch self {
        case .overview: return "house"
        case .cleanup: return "trash"
        case .apps: return "square.grid.2x2"
        case .performance: return "speedometer"
        case .protection: return "shield"
        case .timeline: return "clock.arrow.circlepath"
        case .history: return "arrow.uturn.backward.circle"
        }
    }

    /// What the section will do once it is built. Shown on placeholder screens.
    var summary: String {
        switch self {
        case .overview:
            return tr("A quick look at this Mac.")
        case .cleanup:
            return tr("Find caches, logs, old downloads, large and duplicate files, and leftovers from removed apps.")
        case .apps:
            return tr("See every app with its size and last use, uninstall completely, and control what starts in the background.")
        case .performance:
            return tr("See what is using the processor, memory, disk and battery, explained in plain language.")
        case .protection:
            return tr("Scan for malware, adware, and suspicious background items and browser extensions.")
        case .timeline:
            return tr("A health score with history, showing what changed on this Mac and when.")
        case .history:
            return tr("Everything SiivOS has changed, with a way to put it back.")
        }
    }
}
