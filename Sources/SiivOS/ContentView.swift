import AppKit
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
    /// Whether the sidebar shows icons only. Kept in view state so that changing it can
    /// animate, and saved so that it is remembered between launches.
    @State private var sidebarIsCompact = UserDefaults.standard.bool(forKey: ContentView.compactSidebarKey)

    private static let compactSidebarKey = "sidebarShowsIconsOnly"

    var body: some View {
        // The app lays the two columns out itself. The standard split view ignores a new
        // sidebar width once it is open, so it could not collapse the sidebar to icons,
        // and it offers a way to hide the sidebar, which SiivOS does not want.
        HStack(spacing: 0) {
            SidebarView(selection: $selection, heldBytes: holding.heldBytes, isCompact: $sidebarIsCompact)
                .frame(width: sidebarIsCompact ? SidebarView.compactWidth : SidebarView.fullWidth)
                .clipped()

            Rectangle()
                .fill(SiivOSTheme.divider)
                .frame(width: 1)
                .ignoresSafeArea()

            // Fill the whole column first, so the background covers it even when the
            // screen itself is small, such as a start screen.
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(SiivOSWindowBackground())
        }
        .tint(SiivOSTheme.prominent)
        .onChange(of: sidebarIsCompact) { _, isCompact in
            UserDefaults.standard.set(isCompact, forKey: Self.compactSidebarKey)
        }
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
    /// Width of the sidebar with names.
    static let fullWidth: CGFloat = 240
    /// Width of the sidebar when it shows icons only: room for the window buttons above
    /// and one 34 pt icon per row.
    static let compactWidth: CGFloat = 86

    @Binding var selection: AppSection
    /// What is waiting in the holding area, shown next to History when it is not empty.
    let heldBytes: Int64
    /// True when only the icons are shown.
    @Binding var isCompact: Bool

    @FocusState private var hasFocus: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(AppSection.allCases) { section in
                    SidebarRow(
                        section: section,
                        isSelected: selection == section,
                        trailingText: trailingText(for: section),
                        isCompact: isCompact
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
            // The full logo is wider than the collapsed sidebar, so there the two glints
            // stand in for it, like the app icon. Both take the same height, so the rows
            // below stay where they are.
            if isCompact {
                SiivOSGlintMark()
                    .frame(height: 39)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            } else {
                SiivOSSidebarHeader()
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            collapseButton
        }
        .background {
            // Light mode keeps the Mac's standard translucent sidebar; in dark mode the
            // deep green is drawn over it.
            ZStack {
                SidebarMaterial()
                SiivOSSidebarBackground()
            }
            .ignoresSafeArea()
        }
        // The arrow keys move through the sections once the sidebar has been clicked.
        .focusable()
        .focused($hasFocus)
        .focusEffectDisabled()
        .onMoveCommand { direction in
            move(direction)
        }
    }

    /// Switches between names with icons and icons only.
    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.28)) {
                isCompact.toggle()
            }
        } label: {
            Image(systemName: isCompact ? "chevron.right.2" : "chevron.left.2")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCompact ? tr("Show Section Names") : tr("Show Icons Only"))
        .accessibilityLabel(isCompact ? tr("Show Section Names") : tr("Show Icons Only"))
        .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

/// The Mac's standard sidebar material, which lets a little of the desktop show through.
private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// One section in the sidebar. The selected row is a soft white panel in dark mode and
/// moss with white icon and text in light mode.
private struct SidebarRow: View {
    let section: AppSection
    let isSelected: Bool
    let trailingText: String?
    /// True when only the icon is shown, a little larger.
    let isCompact: Bool
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
                SiivOSIconView(section.icon, size: isCompact ? 34 : 30, isSelected: isOnMoss)
                if !isCompact {
                    // Names keep their full width and fade, so they do not squash or
                    // shorten to "…" while the sidebar narrows.
                    Text(section.title)
                        .foregroundStyle(isOnMoss ? Color.white : Color.primary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.opacity)
                    Spacer(minLength: 8)
                    if let trailingText {
                        Text(trailingText)
                            .font(.callout)
                            .monospacedDigit()
                            .foregroundStyle(isOnMoss ? Color.white.opacity(0.85) : Color.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, isCompact ? 0 : 10)
            .padding(.vertical, isCompact ? 9 : 11)
            .frame(maxWidth: .infinity, alignment: isCompact ? .center : .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        // With only the icon showing, the name appears when the pointer rests on the row.
        .help(section.title)
        .accessibilityLabel(section.title)
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
