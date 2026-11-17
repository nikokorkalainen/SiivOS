import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            detail(for: selection ?? .overview)
        }
    }

    @ViewBuilder
    private func detail(for section: AppSection) -> some View {
        switch section {
        case .overview:
            OverviewView()
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
            if let phase = section.plannedPhase {
                Text("Planned for phase \(phase).")
            }
        }
        .navigationTitle(section.title)
    }
}
