import SiivOSCore
import SwiftUI

/// The first screen: how full the disk is, and what the last check found.
/// Nothing on this screen removes anything.
struct OverviewView: View {
    @ObservedObject var cleanup: CleanupModel
    /// Opens another section of the app.
    let open: (AppSection) -> Void

    @State private var snapshot = SystemSnapshot.current()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(title: tr("Overview"), subtitle: lastCheckedText) {
                    ProminentButton(tr("Check This Mac"), systemImage: "sparkle.magnifyingglass") {
                        snapshot = SystemSnapshot.current()
                        cleanup.scan()
                    }
                    .controlSize(.large)
                    .disabled(cleanup.isScanning)
                    .help(tr("Look for things that can be removed. Checking only looks; nothing is changed."))
                }

                diskSection
                foundSection
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
                QuietCard(section: .protection)
            }
        }
    }

    private var cleanupCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
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
                Button(tr("Review")) {
                    open(.cleanup)
                }
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
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(section: section)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(tr("Open")) {
                    open(section)
                }
            }
        }
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

/// A card for a part of the app that does not exist yet.
private struct QuietCard: View {
    let section: AppSection

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                CardTitle(section: section)
                Text(tr("Coming in a later update"))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
