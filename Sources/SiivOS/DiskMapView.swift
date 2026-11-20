import AppKit
import SiivOSCore
import SwiftUI

/// Shows where the space in the home folder goes: a map with one block for each of the
/// largest items, sized by the space it takes, and the same items as a list. Clicking a
/// folder looks into it. Nothing here removes or changes anything.
struct DiskMapView: View {
    @ObservedObject var model: DiskMapModel
    /// What the last Clutter scan found in app caches that can be removed right now.
    /// Zero when there has been no scan.
    let clearableCacheBytes: Int64
    /// Switches Cleanup to its Clutter view.
    let reviewInClutter: () -> Void

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
            DiskMapResultsView(
                model: model,
                folder: folder,
                clearableCacheBytes: clearableCacheBytes,
                reviewInClutter: reviewInClutter
            )
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

// MARK: - Kinds

/// How a kind of folder is drawn: the three colours of its gradient, the colour of text
/// on it, and its line symbol. The colours are the same in dark and light mode, as the
/// "Disk Map" section of docs/design.md gives them.
private struct KindLook {
    let top: Color
    let middle: Color
    let bottom: Color
    let text: Color
    /// The SF Symbol drawn faintly in a block's corner, or `nil` for none.
    let symbol: String?

    private static func hex(_ value: UInt32) -> Color {
        Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static let deepGreen = hex(0x062A20)

    static func of(_ kind: DiskMapKind) -> KindLook {
        switch kind {
        case .appData:
            return KindLook(top: hex(0x2F9474), middle: hex(0x23775A), bottom: hex(0x175640), text: .white, symbol: "square.3.layers.3d")
        case .media:
            return KindLook(top: hex(0xA0E3C1), middle: hex(0x7FD0A8), bottom: hex(0x5FB48B), text: deepGreen, symbol: "photo")
        case .documents:
            return KindLook(top: hex(0x80C3D9), middle: hex(0x5BA8C4), bottom: hex(0x438EAA), text: deepGreen, symbol: "doc")
        case .downloads:
            return KindLook(top: hex(0xE8CA73), middle: hex(0xD6B04F), bottom: hex(0xBB9538), text: deepGreen, symbol: "arrow.down.to.line")
        case .developer:
            return KindLook(top: hex(0xB5ACE6), middle: hex(0x9A8FD8), bottom: hex(0x8073C3), text: deepGreen, symbol: "chevron.left.forwardslash.chevron.right")
        case .other:
            return KindLook(top: hex(0xA6BBB3), middle: hex(0x8AA39A), bottom: hex(0x718B82), text: deepGreen, symbol: "folder")
        case .smallerItems:
            return KindLook(top: hex(0x4B6159), middle: hex(0x3D5049), bottom: hex(0x30413A), text: .white, symbol: nil)
        }
    }
}

/// One block and row of the map: an item of the folder, or everything too small to list.
private struct MapEntry: Identifiable {
    let id: String
    let name: String
    let sizeBytes: Int64
    let kind: DiskMapKind
    /// What clicking the entry looks into, or `nil` when it cannot be looked into.
    let opens: DiskMapNode?
    /// The item itself, for Show in Finder. `nil` for the smaller-items group.
    let node: DiskMapNode?
    /// The line under the name in the list: the kind, or what the smaller-items group is.
    let detail: String
    /// How the item has changed since an earlier measuring, such as "+6,2 GB", when
    /// that is known and large enough to be worth showing.
    var changeText: String?
    /// Something more to say at the bottom of the block, with a button. Only the
    /// Library block has one.
    var note: BlockNote?

    var look: KindLook { KindLook.of(kind) }
}

/// A sentence at the bottom of a block, with a small button under it.
private struct BlockNote {
    let text: String
    let buttonTitle: String
    let action: () -> Void
}

/// Puts views next to each other and starts a new row when the width runs out.
private struct WrappingRow: Layout {
    var spacing: CGFloat = 16
    var rowSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: result.width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(subviews, width: bounds.width)
        for (index, origin) in result.origins.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: .unspecified
            )
        }
    }

    /// Where each view goes, and how much room they take together.
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + rowSpacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x + size.width)
            x += size.width + spacing
        }
        return (origins, widest, y + rowHeight)
    }
}

private struct DiskMapResultsView: View {
    @ObservedObject var model: DiskMapModel
    let folder: DiskMapNode
    let clearableCacheBytes: Int64
    let reviewInClutter: () -> Void

    /// The entry under the pointer, on the map or in the list. The two are linked: a
    /// block highlights its row, and a row its block.
    @State private var hovered: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: tr("Disk Map"), subtitle: subtitle) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        if let measuredText {
                            Text(measuredText)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Button {
                            model.measureHome()
                        } label: {
                            ButtonLabel(title: tr("Measure Again"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(SiivOSButtonStyle(.standard))
                    }
                }

                breadcrumb

                if let sinceText {
                    Text(sinceText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if entries.isEmpty {
                    Text(tr("This folder is empty, or macOS did not let SiivOS look into it."))
                        .foregroundStyle(.secondary)
                } else {
                    legend

                    MapBlocks(entries: entries, hovered: hovered, setHovered: setHovered) { node in
                        open(node)
                    }
                    .frame(height: 380)

                    infoLine

                    list
                }
            }
            .padding(24)
            .readableWidth()
        }
        // Changes on hover fade briefly, or switch at once with Reduce Motion on.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
    }

    private var subtitle: String {
        tr("%1$@ in %2$@", formatBytes(folder.sizeBytes), folder.name)
    }

    /// When the home folder was measured: the time alone for today, the day as well
    /// when the app has been left open since an earlier day.
    private var measuredText: String? {
        guard let date = model.measuredAt else {
            return nil
        }
        if Calendar.current.isDateInToday(date) {
            return tr("Measured today at %1$@", date.formatted(date: .omitted, time: .shortened))
        }
        return tr("Measured %1$@", date.formatted(date: .abbreviated, time: .shortened))
    }

    /// The kinds on the map right now, each with its colour, in a fixed order.
    private var legend: some View {
        let shown = Set(entries.map { $0.kind })
        return WrappingRow {
            ForEach(DiskMapKind.allCases.filter { shown.contains($0) }, id: \.self) { kind in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(KindLook.of(kind).middle)
                        .frame(width: 11, height: 11)
                    Text(kind.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// What the Library block says about app caches, when Clutter has scanned and found
    /// some that can be cleared. Only on the map of the home folder.
    private func libraryNote(for item: DiskMapNode, home: URL) -> BlockNote? {
        guard isHome,
              clearableCacheBytes > 0,
              clearableCacheBytes <= item.sizeBytes,
              item.url.standardizedFileURL.path == home.appendingPathComponent("Library").standardizedFileURL.path
        else {
            return nil
        }
        return BlockNote(
            text: tr("%1$@ of it is app caches that Clutter can clear.", formatBytes(clearableCacheBytes)),
            buttonTitle: tr("Review in Clutter"),
            action: reviewInClutter
        )
    }

    /// True when the folder shown is the home folder itself.
    private var isHome: Bool {
        model.path.count == 1
    }

    /// The folder's largest items, then one entry for everything too small to list.
    private var entries: [MapEntry] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        var result: [MapEntry] = []
        for child in folder.children where child.sizeBytes > 0 {
            let kind = DiskMap.kind(of: child.url, home: home)
            result.append(
                MapEntry(
                    id: child.url.path,
                    name: child.name,
                    sizeBytes: child.sizeBytes,
                    kind: kind,
                    opens: child.canBeOpened ? child : nil,
                    node: child,
                    detail: kind.title,
                    changeText: changeText(for: child),
                    note: libraryNote(for: child, home: home)
                )
            )
        }
        if folder.otherBytes > 0 {
            let name = folder.otherCount == 1
                ? tr("1 smaller item")
                : tr("%1$@ smaller items", "\(folder.otherCount)")
            result.append(
                MapEntry(
                    id: "smaller-items",
                    name: name,
                    sizeBytes: folder.otherBytes,
                    kind: .smallerItems,
                    opens: folder.smallerItemsNode(named: name),
                    node: nil,
                    detail: tr("Too small to show on their own, added together")
                )
            )
        }
        return result
    }

    private func open(_ node: DiskMapNode) {
        hovered = nil
        model.enter(node)
    }

    // MARK: What grew

    /// By how many bytes an item is larger than at the earlier measuring, when that is
    /// known and worth showing. An item that was not there then counts with all of its
    /// size; one that is smaller now counts as a negative amount.
    private func growth(of item: DiskMapNode) -> Int64? {
        guard let change = model.baseline?.change(of: item, in: folder) else {
            return nil
        }
        let bytes: Int64
        switch change {
        case .new:
            bytes = item.sizeBytes
        case .changed(let amount):
            bytes = amount
        }
        return abs(bytes) >= DiskMapHistory.changeWorthShowing ? bytes : nil
    }

    /// The change as it is shown on a block and in the list: "+6,2 GB" or "−1,1 GB".
    private func changeText(for item: DiskMapNode) -> String? {
        guard let bytes = growth(of: item) else {
            return nil
        }
        return bytes > 0 ? "+" + formatBytes(bytes) : "−" + formatBytes(-bytes)
    }

    /// True when the list of a folder's smaller items is shown. It stands in the same
    /// place as the folder itself, so the folder's own change is not this list's.
    private var isSmallerItemsList: Bool {
        model.path.count >= 2 && model.path[model.path.count - 2].url == folder.url
    }

    /// One or two sentences on what has changed since an earlier measuring: how much
    /// the folder has grown or shrunk, and which items grew most. `nil` when there is
    /// nothing to compare with.
    private var sinceText: String? {
        guard let baseline = model.baseline else {
            // After the very first measuring, say what this place will show next time.
            return isHome && model.wasNotedDown
                ? tr("The next time you measure, SiivOS shows here what has grown since today.")
                : nil
        }
        guard !isSmallerItemsList, let total = baseline.change(of: folder) else {
            return nil
        }
        let when = baseline.date.formatted(date: .abbreviated, time: .shortened)
        var sentences: [String] = []
        if total >= DiskMapHistory.changeWorthShowing {
            sentences.append(tr("%1$@ has grown by %2$@ since %3$@.", folder.name, formatBytes(total), when))
        } else if total <= -DiskMapHistory.changeWorthShowing {
            sentences.append(tr("%1$@ has shrunk by %2$@ since %3$@.", folder.name, formatBytes(-total), when))
        } else {
            sentences.append(tr("%1$@ is about the same size as on %2$@.", folder.name, when))
        }

        let grown = folder.children
            .compactMap { item -> (name: String, bytes: Int64)? in
                guard let bytes = growth(of: item), bytes > 0 else {
                    return nil
                }
                return (item.name, bytes)
            }
            .sorted { $0.bytes > $1.bytes }
            .prefix(3)
            .map { $0.name + " (+" + formatBytes($0.bytes) + ")" }
        if !grown.isEmpty {
            sentences.append(tr("Grew most: %1$@.", grown.joined(separator: ", ")))
        }
        return sentences.joined(separator: " ")
    }

    /// Follows the pointer: an entry is hovered when the pointer comes over it, and
    /// stops being hovered when the pointer leaves it for somewhere that is not an entry.
    private func setHovered(_ id: String, _ isInside: Bool) {
        if isInside {
            hovered = id
        } else if hovered == id {
            hovered = nil
        }
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

    // MARK: Info line

    /// One line under the map. Normally a hint; while the pointer is over an entry, that
    /// entry's name, kind, size and share. This is where blocks too small for a label
    /// get their name.
    @ViewBuilder
    private var infoLine: some View {
        if let entry = entries.first(where: { $0.id == hovered }) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.look.middle)
                    .frame(width: 12, height: 12)
                Text(entry.name)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.kind.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(sizeAndShare(of: entry))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                if entry.opens != nil {
                    Text(entry.kind == .smallerItems ? tr("Click to list them.") : tr("Click to look inside."))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(minHeight: 36, alignment: .center)
        } else {
            Text(tr("Click a folder to look inside. Apps and photo, video and music libraries count as one item and are never looked into."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 36, alignment: .topLeading)
        }
    }

    private func sizeAndShare(of entry: MapEntry) -> String {
        let percent = share(of: entry).formatted(.percent.precision(.fractionLength(0)))
        let size = formatBytes(entry.sizeBytes)
        return isHome
            ? tr("%1$@, %2$@ of your home folder", size, percent)
            : tr("%1$@, %2$@ of %3$@", size, percent, folder.name)
    }

    // MARK: List

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                if entry.id != entries.first?.id {
                    ThemedDivider()
                }
                MapRow(
                    entry: entry,
                    share: share(of: entry),
                    isHovered: hovered == entry.id,
                    setHovered: setHovered
                ) {
                    if let node = entry.opens {
                        open(node)
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

// MARK: - Map

/// The map itself: one block for each entry, as large as its share of the folder.
private struct MapBlocks: View {
    let entries: [MapEntry]
    let hovered: String?
    let setHovered: (String, Bool) -> Void
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
                    MapBlock(
                        entry: entry,
                        rect: rects[index],
                        isHovered: hovered == entry.id,
                        isFadedBack: hovered != nil && hovered != entry.id,
                        setHovered: setHovered,
                        open: open
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// One block of the map: a soft gradient in its kind's colour with a sheen and edge
/// lines, a faint symbol of the kind in the corner, and the name and size where there is
/// room. Under the pointer it brightens and gets a white ring, while the others fade back.
private struct MapBlock: View {
    let entry: MapEntry
    let rect: MapRect
    let isHovered: Bool
    /// True while another block is under the pointer.
    let isFadedBack: Bool
    let setHovered: (String, Bool) -> Void
    let open: (DiskMapNode) -> Void

    /// The gap between blocks.
    private static let gap: CGFloat = 3

    private var width: CGFloat { max(0, CGFloat(rect.width) - Self.gap) }
    private var height: CGFloat { max(0, CGFloat(rect.height) - Self.gap) }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: min(8, min(width, height) / 2), style: .continuous)
    }

    /// The kind symbol is about a third of the block's shorter side, and left out when
    /// that would make it too small to read.
    private var symbolSize: CGFloat { min(width, height) / 3 }

    /// The size, followed where there is room by how it has changed since an earlier
    /// measuring.
    private var sizeLine: String {
        let size = formatBytes(entry.sizeBytes)
        guard let change = entry.changeText, width >= 170 else {
            return size
        }
        return size + " · " + change
    }

    var body: some View {
        Button {
            if let node = entry.opens {
                open(node)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                shape.fill(
                    LinearGradient(
                        colors: [entry.look.top, entry.look.middle, entry.look.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                // A faint sheen in the top left corner.
                shape.fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0)],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: max(width, height) * 0.55
                    )
                )
                // A light line along the top edge and a dark one along the bottom.
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.30))
                        .frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color.black.opacity(0.16))
                        .frame(height: 1)
                }

                if let symbol = entry.look.symbol, symbolSize >= 28 {
                    Image(systemName: symbol)
                        .font(.system(size: symbolSize, weight: symbolSize > 70 ? .ultraLight : .light))
                        .foregroundStyle(entry.look.text.opacity(isHovered ? 0.22 : 0.16))
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                // The name and size only where there is room to read them. Smaller
                // blocks get theirs in the info line under the map.
                if width >= 92, height >= 46 {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.name)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(sizeLine)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .opacity(0.85)
                    }
                    .foregroundStyle(entry.look.text)
                    .padding(11)
                }

                if isHovered {
                    // Softer than the design notes give (2 pt at 78 %): the owner found
                    // the first version too strong.
                    shape.strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5)
                    // A small round badge on blocks that open.
                    if entry.opens != nil, width >= 40, height >= 40 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(entry.look.text)
                            .frame(width: 22, height: 22)
                            .background(Color.white.opacity(0.24), in: Circle())
                            .padding(8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(shape)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The note sits on top of the block, not inside its button, so that the note's
        // own button takes its clicks. A click on the sentence still opens the block.
        .overlay(alignment: .bottomLeading) {
            if let note = entry.note, width >= 240, height >= 150 {
                VStack(alignment: .leading, spacing: 8) {
                    Text(note.text)
                        .font(.system(size: 12))
                        .foregroundStyle(entry.look.text.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                    Button(action: note.action) {
                        Text(note.buttonTitle)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(entry.look.text)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.22), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(11)
                .frame(maxWidth: min(width, 340), alignment: .leading)
            }
        }
        // The hover is kept gentle: a slight lift and brightening for the block under
        // the pointer, and only a slight step back for the others.
        .shadow(
            color: Color.black.opacity(isHovered ? 0.26 : 0.22),
            radius: isHovered ? 9 : 2,
            x: 0,
            y: isHovered ? 3 : 1
        )
        .brightness(isHovered ? 0.035 : 0)
        .saturation(isFadedBack ? 0.93 : 1)
        .opacity(isFadedBack ? 0.84 : 1)
        .onHover { isInside in
            setHovered(entry.id, isInside)
        }
        .position(
            x: CGFloat(rect.x) + CGFloat(rect.width) / 2,
            y: CGFloat(rect.y) + CGFloat(rect.height) / 2
        )
        // Drawn above its neighbours while under the pointer, so its shadow falls on them.
        .zIndex(isHovered ? 1 : 0)
    }
}

/// One line of the list under the map: a square in the kind's colour, the name with the
/// kind under it, a bar for its share of the folder, and the size. It is tinted while its block is under
/// the pointer, and the pointer over the row highlights the block.
private struct MapRow: View {
    let entry: MapEntry
    /// The entry's share of the folder, from 0 to 1.
    let share: Double
    let isHovered: Bool
    let setHovered: (String, Bool) -> Void
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(entry.look.middle)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if entry.opens != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.changeText.map { entry.detail + " · " + $0 } ?? entry.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                MeterBar(fraction: share, color: entry.look.middle)
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
            .background(Color.gray.opacity(isHovered ? 0.09 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isInside in
            setHovered(entry.id, isInside)
        }
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
