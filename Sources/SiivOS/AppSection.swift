import Foundation

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
        case .overview: return "Overview"
        case .cleanup: return "Cleanup"
        case .apps: return "Apps"
        case .performance: return "Performance"
        case .protection: return "Protection"
        case .timeline: return "Health Timeline"
        case .history: return "History"
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
            return "A quick look at this Mac."
        case .cleanup:
            return "Find caches, logs, old downloads, large and duplicate files, and leftovers from removed apps."
        case .apps:
            return "See every app with its size and last use, uninstall completely, and control what starts in the background."
        case .performance:
            return "See what is using the processor, memory, disk and battery, explained in plain language."
        case .protection:
            return "Scan for malware, adware, and suspicious background items and browser extensions."
        case .timeline:
            return "A health score with history, showing what changed on this Mac and when."
        case .history:
            return "Everything SiivOS has changed, with a way to put it back."
        }
    }

    /// The production-plan phase that delivers this section (see PLAN.md).
    var plannedPhase: Int? {
        switch self {
        case .overview, .history: return nil
        case .cleanup: return 3
        case .apps: return 4
        case .performance: return 5
        case .protection: return 6
        case .timeline: return 7
        }
    }
}
