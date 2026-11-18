import SiivOSCore
import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .overview
    /// Kept here so that scan results survive a visit to another section,
    /// and so that Overview and Cleanup show the same check.
    @StateObject private var cleanup = CleanupModel()
    /// Kept here so that the app list is only measured once.
    @StateObject private var apps = AppsModel()
    /// Kept here so that the charts keep their history during a short visit elsewhere.
    @StateObject private var performance = PerformanceModel()
    @ObservedObject private var holding = HoldingStatus.shared

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                HStack(spacing: 10) {
                    SiivOSIconView(section.icon, isSelected: selection == section)
                    Text(section.title)
                }
                .padding(.vertical, 8)
                .badge(historyBadge(for: section))
            }
            .scrollContentBackground(.hidden)
            .background(SiivOSSidebarBackground())
            .safeAreaInset(edge: .top, spacing: 0) {
                SiivOSSidebarHeader()
            }
            .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            detail(for: selection ?? .overview)
                .background(SiivOSWindowBackground())
        }
        .tint(SiivOSTheme.prominent)
        .onAppear {
            holding.refresh()
        }
    }

    /// History shows how much is waiting in the holding area. Nothing else has a badge.
    private func historyBadge(for section: AppSection) -> Text? {
        guard section == .history, holding.heldBytes > 0 else {
            return nil
        }
        return Text(formatBytes(holding.heldBytes))
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView(cleanup: cleanup, open: { selection = $0 })
        case .cleanup:
            CleanupView(model: cleanup)
        case .apps:
            AppsView(model: apps)
        case .performance:
            PerformanceView(model: performance, cleanup: cleanup, open: { selection = $0 })
        case .history:
            HistoryView()
        default:
            ComingSoonView(section: section)
        }
    }
}

/// Placeholder for sections that a later phase of the plan will build.
struct ComingSoonView: View {
    let section: AppSection

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(section.title)
            } icon: {
                SiivOSIconView(section.icon, size: 34)
            }
        } description: {
            Text(section.summary)
            Text(tr("Coming in a later update"))
        }
        .navigationTitle(section.title)
    }
}
