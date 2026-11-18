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

    /// The section's icon from the SiivOS icon set.
    var icon: SiivOSIcon {
        switch self {
        case .overview: return .overview
        case .cleanup: return .cleanup
        case .apps: return .apps
        case .performance: return .performance
        case .protection: return .protection
        case .timeline: return .timeline
        case .history: return .history
        }
    }
}
