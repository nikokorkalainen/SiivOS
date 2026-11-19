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
    /// Not one of the seven sections: pinned at the bottom of the sidebar, apart from them.
    case settings

    var id: AppSection { self }

    /// The seven sections listed in the sidebar, in order. Settings is not among them.
    static let mainSections: [AppSection] = allCases.filter { $0 != .settings }

    var title: String {
        switch self {
        case .overview: return tr("Overview")
        case .cleanup: return tr("Cleanup")
        case .apps: return tr("Apps")
        case .performance: return tr("Performance")
        case .protection: return tr("Protection")
        case .timeline: return tr("Health Timeline")
        case .history: return tr("History")
        case .settings: return tr("Settings")
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
        case .settings: return .settings
        }
    }
}
