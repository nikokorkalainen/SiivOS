import AppKit
import SiivOSCore
import SwiftUI

/// Shows where the space in the home folder goes: a map with one block for each of the
/// largest items, sized by the space it takes, and the same items as a list. Clicking a
/// folder looks into it. Nothing here removes or changes anything.
struct DiskMapView: View {
    @ObservedObject var model: DiskMapModel

    var body: some View {
        if model.isMeasuring {
            VStack(spacing: 18) {
                LoadingView(text: progressText)
                Button(tr("Stop")) {
                    model.stop()
                }
                .buttonStyle(SiivOSButtonStyle(.standard))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let folder = model.current {
            DiskMapResultsView(model: model, folder: folder)
        } else {
            startScreen
        }
    }

    private var progressText: String {
        model.measuringName.isEmpty ? tr("Getting ready…") : tr("Measuring: %1$@…", model.measuringName)
    }

    /// The screen before the first measuring, in the open layout.
    private var startScreen: some View {
        CenteredScreen {
            SiivOSIconView(.cleanup, size: 72)
            Text(tr("See where the space goes"))
                .font(.system(size: 22, weight: .semibold))
            VStack(spacing: 6) {
                Text(tr("SiivOS measures every folder in your home folder and draws the largest as blocks, each as big as the space it takes."))
                Text(tr("Measuring only looks. Nothing is changed. It can take a minute or two."))
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
            .fixedSize(horizontal: false, vertical: true)

            ProminentButton(tr("Measure My Home Folder")) {
                model.measureHome()
            }
            .padding(.top, 4)

            Text(tr("macOS may ask for permission to look in your Desktop, Documents and Downloads folders."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 500)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }
}

/// One block or row of the map: an item of the folder, or everything too small to list.
private struct MapEntry: Identifiable {
    let id: String
    let name: String
    let sizeBytes: Int64
    /// The item itself, or `nil` for the block that stands for the small items.
    let node: DiskMapNode?
    /// The place among the entries, largest first. It picks the shade of the block.
    let rank: Int

    /// How strong the block's colour is. The largest is the strongest, and the block
    /// for small items is the faintest. Kept moderate so that the text on it stays
    /// readable in both dark and light mode.
    var shade: Double {
        node == nil ? 0.10 : max(0.16, 0.56 - Double(rank) * 0.03)
    }
}

private struct DiskMapResultsView: View {
    @ObservedObject var model: DiskMapModel
    let folder: DiskMapNode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("Disk Map"), subtitle: subtitle) {
                    Button {
                        model.measureHome()
                    } label: {
                        ButtonLabel(title: tr("Measure Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SiivOSButtonStyle(.standard))
                }

                breadcrumb

                if entries.isEmpty {
                    Text(tr("This folder is empty, or macOS did not let SiivOS look into it."))
                        .foregroundStyle(.secondary)
                } else {
                    MapBlocks(entries: entries) { node in
                        model.enter(node)
                    }
                    .frame(height: 340)

                    list
                }

                Text(tr("Apps and photo, video and music libraries are shown as one item and are never looked into. Click a folder to look into it."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .readableWidth()
        }
    }

    private var subtitle: String {
        tr("%1$@ in %2$@", formatBytes(folder.sizeBytes), folder.name)
    }

    /// The folder's largest items, then one entry for everything too small to list.
    private var entries: [MapEntry] {
        var result: [MapEntry] = []
        for (index, child) in folder.children.enumerated() where child.sizeBytes > 0 {
            result.append(MapEntry(id: child.url.path, name: child.name, sizeBytes: child.sizeBytes, node: child, rank: index))
        }
        if folder.otherBytes > 0 {
            let name = folder.otherCount == 1
                ? tr("1 smaller item")
                : tr("%1$@ smaller items", "\(folder.otherCount)")
            result.append(MapEntry(id: "other", name: name, sizeBytes: folder.otherBytes, node: nil, rank: result.count))
        }
        return result
    }

    /// The way down from the home folder. Every step but the last goes back up to it.
    private var breadcrumb: some View {
        HStack(spacing: 6) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                if index == model.path.count - 1 {
                    Text(step.name)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                } else {
                    Button(step.name) {
                        model.goBack(to: index)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.siivosTint)
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                if entry.id != entries.first?.id {
                    ThemedDivider()
                }
                MapRow(entry: entry, share: share(of: entry)) {
                    if let node = entry.node {
                        model.enter(node)
                    }
                }
            }
        }
        .cardBackground()
    }

    private func share(of entry: MapEntry) -> Double {
        folder.sizeBytes > 0 ? Double(entry.sizeBytes) / Double(folder.sizeBytes) : 0
    }
}

/// The map itself: one block for each entry, as large as its share of the folder.
private struct MapBlocks: View {
    let entries: [MapEntry]
    let open: (DiskMapNode) -> Void

    var body: some View {
        GeometryReader { proxy in
            let rects = Treemap.layout(
                sizes: entries.map { Double($0.sizeBytes) },
                width: Double(proxy.size.width),
                height: Double(proxy.size.height)
            )
            ZStack(alignment: .topLeading) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    MapBlock(entry: entry, rect: rects[index], open: open)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One block of the map. A folder that can be looked into is a button.
private struct MapBlock: View {
    let entry: MapEntry
    let rect: MapRect
    let open: (DiskMapNode) -> Void

    /// A thin gap between blocks.
    private static let gap: CGFloat = 2

    private var width: CGFloat { max(0, CGFloat(rect.width) - Self.gap) }
    private var height: CGFloat { max(0, CGFloat(rect.height) - Self.gap) }

    var body: some View {
        Button {
            if let node = entry.node, node.canBeOpened {
                open(node)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.siivosTint.opacity(entry.shade))
                // The name and size only where there is room to read them.
                if width > 76, height > 40 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(formatBytes(entry.sizeBytes))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(7)
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.name + ", " + formatBytes(entry.sizeBytes))
        .position(
            x: CGFloat(rect.x) + CGFloat(rect.width) / 2,
            y: CGFloat(rect.y) + CGFloat(rect.height) / 2
        )
    }
}

/// One line of the list under the map: a mark in the block's shade, the name, a bar for
/// its share of the folder, and the size.
private struct MapRow: View {
    let entry: MapEntry
    /// The entry's share of the folder, from 0 to 1.
    let share: Double
    let open: () -> Void

    private var canBeOpened: Bool {
        entry.node?.canBeOpened == true
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.siivosTint.opacity(entry.shade))
                    .frame(width: 12, height: 12)
                Text(entry.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if canBeOpened {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                MeterBar(fraction: share)
                    .frame(width: 120)
                Text(share.formatted(.percent.precision(.fractionLength(0))))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
                Text(formatBytes(entry.sizeBytes))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 76, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.node?.url.path ?? entry.name)
        .contextMenu {
            if let node = entry.node {
                Button(tr("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([node.url])
                }
            }
        }
    }
}
