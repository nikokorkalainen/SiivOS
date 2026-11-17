import SiivOSCore
import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .overview
    /// Kept here so that scan results survive a visit to another section,
    /// and so that Overview and Cleanup show the same check.
    @StateObject private var cleanup = CleanupModel()
    /// Kept here so that the app list is only measured once.
    @StateObject private var apps = AppsModel()
    @ObservedObject private var holding = HoldingStatus.shared

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .badge(historyBadge(for: section))
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detail(for: selection ?? .overview)
        }
        .tint(Color.siivosMoss)
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
            Label(section.title, systemImage: section.symbol)
        } description: {
            Text(section.summary)
            Text(tr("Coming in a later update"))
        }
        .navigationTitle(section.title)
    }
}
