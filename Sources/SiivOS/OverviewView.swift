import SiivOSCore
import SwiftUI

/// The first screen: how full the disk is, and what the last check found.
/// Nothing on this screen removes anything.
struct OverviewView: View {
    @ObservedObject var cleanup: CleanupModel
    /// The health score and the readings of free space over time.
    @ObservedObject var timeline: TimelineModel
    /// How much is waiting in the holding area, for the History card.
    @ObservedObject private var holding = HoldingStatus.shared
    /// Opens another section of the app.
    let open: (AppSection) -> Void

    @State private var snapshot = SystemSnapshot.current()
    /// How tall each card's content is, so that every card can be as tall as the tallest.
    @State private var cardContentHeights: [AppSection: CGFloat] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: tr("Overview"), subtitle: lastCheckedText) {
                    ProminentButton(tr("Check This Mac"), systemImage: "sparkle.magnifyingglass") {
                        snapshot = SystemSnapshot.current()
                        cleanup.scan()
                    }
                    .disabled(cleanup.isScanning)
                    .help(tr("Look for things that can be removed. Checking only looks; nothing is changed."))
                }

                diskSection
                foundSection
                spaceOverTimeSection
                macSection
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(tr("Overview"))
    }

    // MARK: - Disk

    private var diskSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(freeSpaceText)
                .font(.title2)
            DiskBar(usedFraction: usedFraction, safeFraction: safeFraction)
            HStack(spacing: 16) {
                LegendItem(color: Color.siivosTint, text: tr("Used"))
                LegendItem(color: Color.siivosTint.opacity(0.45), text: tr("Safe to remove"))
                LegendItem(color: SiivOSTheme.divider, text: tr("Free"))
            }
        }
    }

    private var freeSpaceText: String {
        guard let total = snapshot.diskTotalBytes, let available = snapshot.diskAvailableBytes else {
            return tr("The disk could not be read.")
        }
        return tr("%1$@ free of %2$@", formatBytes(available), formatBytes(total))
    }

    /// The part of the disk that is in use and not safe to remove, from 0 to 1.
    private var usedFraction: Double {
        max(0, (snapshot.diskUsedFraction ?? 0) - safeFraction)
    }

    /// The part of the disk taken by things the last check found safe to remove, from 0 to 1.
    private var safeFraction: Double {
        guard let total = snapshot.diskTotalBytes, total > 0 else {
            return 0
        }
        let fraction = Double(cleanup.safeToRemoveBytes) / Double(total)
        return min(max(0, fraction), snapshot.diskUsedFraction ?? 0)
    }

    private var lastCheckedText: String {
        if cleanup.isScanning {
            return tr("Checking now…")
        }
        guard let date = cleanup.lastScanDate else {
            return tr("Not checked yet")
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return tr("Last checked: %1$@", formatter.string(from: date))
    }

    // MARK: - What the check found

    private var foundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("What the check found"))
                .font(.title3)
                .bold()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                cleanupCard
                linkCard(.apps, text: tr("See your apps, their size and what starts in the background."))
                linkCard(.performance, text: tr("See what is using the processor, memory, disk and battery right now."))
                linkCard(.protection, text: tr("Check the Mac's built-in protection, what starts by itself, browser extensions and profiles."))
                timelineCard
                historyCard
            }
        }
    }

    /// What is waiting in the holding area, and a way to History.
    private var historyCard: some View {
        areaCard(.history, buttonTitle: tr("Open")) {
            CardTitle(section: .history)
            if holding.heldBytes > 0 {
                Text(formatBytes(holding.heldBytes))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text(tr("in the holding area"))
                    .foregroundStyle(.secondary)
                Text(
                    holding.isWorthPointingOut
                        ? tr("That is more than the %1$@ you chose to be told about. Deleting items for good in History frees the space.", formatBytes(holding.settings.warnAboveBytes))
                        : tr("Put items back, or delete them permanently to free the space.")
                )
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("Everything SiivOS has changed, with a way to put it back. The holding area is empty."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The health score, once there is one, and a way to the reasons behind it.
    private var timelineCard: some View {
        areaCard(.timeline, buttonTitle: tr("Open")) {
            CardTitle(section: .timeline)
            if let total = timeline.latestTotal {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)")
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text(tr("of 100"))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Text(tr("The health score. See the reasons behind it and what has changed on this Mac."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(tr("A health score with its reasons, and what has changed on this Mac and when."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Free space over time

    /// Shown once there are at least two readings to draw a line between.
    @ViewBuilder
    private var spaceOverTimeSection: some View {
        if timeline.freeSpacePoints.count > 1 {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("Free space over time"))
                    .font(.title3)
                    .bold()
                Card {
                    FreeSpaceTrend(readings: timeline.freeSpacePoints, diskTotalBytes: timeline.diskTotalBytes)
                }
            }
        }
    }

    private var cleanupCard: some View {
        areaCard(.cleanup, buttonTitle: tr("Review")) {
            CardTitle(section: .cleanup, iconSize: 34)
            if cleanup.isScanning {
                LoadingView(text: tr("Checking now…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            } else if cleanup.report == nil {
                Text(tr("Check this Mac to see what can be removed."))
                    .foregroundStyle(.secondary)
            } else {
                Text(formatBytes(cleanup.safeToRemoveBytes))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text(tr("safe to remove"))
                    .foregroundStyle(.secondary)
                Text(ownFilesText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var ownFilesText: String {
        let count = cleanup.ownFilesCount
        if count == 0 {
            return tr("None of your own files need a look.")
        }
        if count == 1 {
            return tr("1 of your own files to look through.")
        }
        return tr("%1$@ of your own files to look through.", "\(count)")
    }

    /// A card that says what a section is for and opens it.
    private func linkCard(_ section: AppSection, text: String) -> some View {
        areaCard(section, buttonTitle: tr("Open")) {
            CardTitle(section: section)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// One card of the grid: its content, then the button that opens the section. Every
    /// card is as tall as the tallest one, and the buttons line up along the bottom.
    private func areaCard<Content: View>(
        _ section: AppSection,
        buttonTitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 8) {
                    content()
                }
                // Measured before the shared height is applied, so this is the height
                // the content needs by itself.
                .background(
                    HeightReader { height in
                        cardContentHeights[section] = height
                    }
                )
                .frame(minHeight: tallestCardContent, alignment: .topLeading)

                Button(buttonTitle) {
                    open(section)
                }
                .buttonStyle(SiivOSButtonStyle(.small))
            }
        }
    }

    private var tallestCardContent: CGFloat {
        cardContentHeights.values.max() ?? 0
    }

    // MARK: - This Mac

    private var macSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("This Mac"))
                .font(.title3)
                .bold()
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    FactRow(label: "macOS", value: snapshot.osVersion)
                    ThemedDivider()
                    FactRow(label: tr("Processor cores"), value: "\(snapshot.processorCount)")
                    ThemedDivider()
                    FactRow(label: tr("Memory"), value: memory(snapshot.physicalMemoryBytes))
                    ThemedDivider()
                    FactRow(label: tr("Time since restart"), value: uptime(snapshot.uptimeSeconds))
                }
            }
        }
    }

    private func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? tr("Unknown")
    }
}

/// Reports the height of the view it sits behind, now and whenever it changes.
private struct HeightReader: View {
    let report: (CGFloat) -> Void

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear {
                    report(proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, height in
                    report(height)
                }
        }
    }
}

/// The disk drawn as one bar: used, safe to remove, and free.
private struct DiskBar: View {
    let usedFraction: Double
    let safeFraction: Double

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.siivosTint)
                    .frame(width: proxy.size.width * usedFraction)
                Rectangle()
                    .fill(Color.siivosTint.opacity(0.45))
                    .frame(width: proxy.size.width * safeFraction)
                Rectangle()
                    .fill(SiivOSTheme.divider)
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
    }
}

private struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The name of a section with its icon, as the heading of a card.
private struct CardTitle: View {
    let section: AppSection
    /// 34 pt for the Cleanup card, 30 pt for the others.
    var iconSize: CGFloat = 30

    var body: some View {
        HStack(spacing: 10) {
            SiivOSIconView(section.icon, size: iconSize)
            Text(section.title)
                .font(.headline)
        }
    }
}
