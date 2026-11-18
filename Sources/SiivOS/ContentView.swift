import SiivOSCore
import SwiftUI

struct ContentView: View {
    @State private var selection: AppSection = .overview
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
            SidebarView(selection: $selection, heldBytes: holding.heldBytes)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240)
        } detail: {
            // Fill the whole column first, so the background covers it even when the
            // screen itself is small, such as a start screen.
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SiivOSWindowBackground())
                .modifier(ThemedToolbar())
        }
        .tint(SiivOSTheme.prominent)
        .onAppear {
            holding.refresh()
        }
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

// MARK: - Sidebar

/// The sidebar, drawn by the app itself. A standard list would draw the selected row in
/// the accent colour chosen in System Settings, which the app cannot change.
private struct SidebarView: View {
    @Binding var selection: AppSection
    /// What is waiting in the holding area, shown next to History when it is not empty.
    let heldBytes: Int64

    @FocusState private var hasFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section,
                        trailingText: trailingText(for: section)
                    ) {
                        selection = section
                        hasFocus = true
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            SiivOSSidebarHeader()
        }
        .background(SiivOSSidebarBackground())
        // The arrow keys move through the sections once the sidebar has been clicked.
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            move(direction)
        }
    }

    /// History shows how much is waiting in the holding area. Nothing else has a label.
    private func trailingText(for section: AppSection) -> String? {
        guard section == .history, heldBytes > 0 else {
            return nil
        }
        return formatBytes(heldBytes)
    }

    private func move(_ direction: MoveCommandDirection) {
        let sections = AppSection.allCases
        guard let index = sections.firstIndex(of: selection) else {
            return
        }
        switch direction {
        case .up:
            if index > 0 {
                selection = sections[index - 1]
            }
        case .down:
            if index < sections.count - 1 {
                selection = sections[index + 1]
            }
        default:
            break
        }
    }
}

/// One section in the sidebar. The selected row is a soft white panel in dark mode and
/// moss with white icon and text in light mode.
private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let trailingText: String?
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Moss green (#2F7A5F).
    private static let moss = Color(red: 47.0 / 255.0, green: 122.0 / 255.0, blue: 95.0 / 255.0)

    /// True when the row is drawn on moss, which needs a white icon and white text.
    private var isOnMoss: Bool {
        isSelected && colorScheme != .dark
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SiivOSIconView(section.icon, isSelected: isOnMoss)
                Text(section.title)
                    .foregroundStyle(isOnMoss ? Color.white : Color.primary)
                Spacer(minLength: 8)
                if let trailingText {
                    Text(trailingText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(isOnMoss ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        guard isSelected else {
            return Color.clear
        }
        return colorScheme == .dark ? Color.white.opacity(0.14) : Self.moss
    }
}

// MARK: - Sections that are not built yet

/// Placeholder for sections that a later phase of the plan will build: the section's
/// icon, its name and what it will do, in the open layout with nothing behind it.
struct ComingSoonView: View {
    let section: AppSection

    var body: some View {
        CenteredScreen {
            SiivOSIconView(section.icon, size: 72)
            Text(section.title)
                .font(.system(size: 22, weight: .semibold))
            Text(section.summary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("Coming in a later update"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .navigationTitle(section.title)
    }
}
