import AppKit
import SiivOSCore
import SwiftUI

/// Finds clutter and lets the user choose what to remove.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel

    var body: some View {
        content
            .navigationTitle(tr("Cleanup"))
            .sheet(item: $model.pendingPlan) { plan in
                RemovalPlanSheet(
                    plan: plan,
                    onConfirm: { model.confirmPendingPlan() },
                    onCancel: { model.pendingPlan = nil }
                )
            }
            .alert(
                "SiivOS",
                isPresented: isShowingMessage,
                presenting: model.message
            ) { _ in
                Button("OK") {}
            } message: { text in
                Text(text)
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            LoadingView(text: progressText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.report != nil {
            CleanupResultsView(model: model)
        } else {
            CleanupStartView(model: model)
        }
    }

    private var progressText: String {
        model.scanningTitle.isEmpty ? tr("Getting ready…") : tr("Checking: %1$@…", model.scanningTitle)
    }

    /// True while a problem is being shown to the user.
    private var isShowingMessage: Binding<Bool> {
        Binding(
            get: { model.message != nil },
            set: { isShown in
                if !isShown { model.message = nil }
            }
        )
    }
}

/// The Cleanup screen before the first scan: what a scan looks for, in the open layout
/// from the design notes, with nothing behind it.
private struct CleanupStartView: View {
    @ObservedObject var model: CleanupModel

    var body: some View {
        CenteredScreen {
            SiivOSIconView(.cleanup, size: 72)
            Text(tr("Scan this Mac for clutter"))
                .font(.system(size: 22, weight: .semibold))
            VStack(spacing: 6) {
                Text(tr("SiivOS looks for app caches, logs, leftovers from removed apps, old downloads, large files and duplicate files."))
                Text(tr("Scanning only looks. Nothing is removed until you tick items and confirm."))
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
            .fixedSize(horizontal: false, vertical: true)

            ProminentButton(tr("Scan for Clutter")) {
                model.scan()
            }
            .padding(.top, 4)

            ThemedDivider()
                .frame(maxWidth: 500)
                .padding(.vertical, 8)

            HStack(alignment: .top, spacing: 56) {
                StartColumn(
                    title: tr("Safe to remove"),
                    items: [tr("App caches"), tr("Logs"), tr("Leftovers from removed apps")]
                )
                StartColumn(
                    title: tr("Check first"),
                    items: [tr("Old downloads"), tr("Large files"), tr("Duplicate files")]
                )
            }

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

/// One of the two short columns on the start screen: a heading and what belongs under it.
private struct StartColumn: View {
    let title: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            ForEach(items, id: \.self) { item in
                Text(item)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Everything a scan found, in two parts, with the action bar pinned to the bottom.
private struct CleanupResultsView: View {
    @ObservedObject var model: CleanupModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: tr("Cleanup"),
                    subtitle: tr("Tick what you want to remove. Nothing changes until you confirm.")
                ) {
                    Button {
                        model.scan()
                    } label: {
                        ButtonLabel(title: tr("Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SiivOSButtonStyle(.standard))
                    .disabled(model.isWorking)
                }

                if let notice = model.lastRemoval {
                    RemovalBanner(model: model, notice: notice)
                }

                if let note = model.settingsNote {
                    Label(note, systemImage: "slider.horizontal.3")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                CleanupPartView(
                    model: model,
                    title: tr("Safe to remove"),
                    heading: tr("Files apps and macOS make for themselves. Removing them does not touch your documents."),
                    sections: model.safeSections,
                    isSafe: true
                )
                CleanupPartView(
                    model: model,
                    title: tr("Check first"),
                    heading: tr("These are your own files. Look at each one before you tick it."),
                    sections: model.checkFirstSections,
                    isSafe: false
                )

                NeverListedView()
            }
            .padding(24)
            .readableWidth()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            CleanupActionBar(model: model)
        }
    }
}

/// Says what the last removal did, and offers to undo it.
private struct RemovalBanner: View {
    @ObservedObject var model: CleanupModel
    let notice: RemovalNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Color.siivosTint)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button {
                model.undoLastRemoval()
            } label: {
                ButtonLabel(title: tr("Undo"), systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(SiivOSButtonStyle(.standard))
            .disabled(model.isWorking)
            Button {
                model.dismissRemovalNotice()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(tr("Hide this message"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var text: String {
        let size = formatBytes(notice.bytes)
        if notice.itemCount == 1 {
            return tr("Moved 1 item (%1$@) to the holding area. Delete it permanently in History to free the space.", size)
        }
        return tr(
            "Moved %1$@ items (%2$@) to the holding area. Delete them permanently in History to free the space.",
            "\(notice.itemCount)", size
        )
    }
}

/// One of the two parts of the list: "Safe to remove" or "Check first".
private struct CleanupPartView: View {
    @ObservedObject var model: CleanupModel
    let title: String
    let heading: String
    let sections: [ScanReport.Section]
    /// Safe groups can be ticked all at once. The user's own files cannot.
    let isSafe: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title2)
                .bold()
            Text(heading)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(sections) { section in
                CleanupGroupView(model: model, section: section, isSafe: isSafe)
            }
        }
    }
}

/// What one kind of check found, as a group that can be opened and closed.
private struct CleanupGroupView: View {
    @ObservedObject var model: CleanupModel
    let section: ScanReport.Section
    let isSafe: Bool

    @State private var isOpen = true

    /// Long lists are cut off here, largest items first, to keep the screen quick.
    private static let rowLimit = 100

    /// The checks whose explanation says something specific about each item.
    private static let sectionsWithExplanations: Set<String> = [
        "leftovers", "developer", "old-downloads", "large-files", "duplicates"
    ]

    private var shownFindings: [Finding] {
        Array(section.findings.prefix(Self.rowLimit))
    }

    /// The shown items that Tick All ticks: the ones labelled Safe to remove that are
    /// not held back. Items labelled Check first are only ever ticked one by one.
    private var tickableFindings: [Finding] {
        shownFindings.filter { $0.heldBackReason == nil && $0.safety == .safeToRemove }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                details
                    .padding(.top, 10)
                    .padding(.leading, 26)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                isOpen.toggle()
            } label: {
                HStack(spacing: 8) {
                    DisclosureArrow(isOpen: isOpen)
                    Text(section.title)
                        .font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()

            if isSafe && !tickableFindings.isEmpty {
                Button(model.areAllSelected(tickableFindings) ? tr("Untick All") : tr("Tick All")) {
                    model.setAllSelected(tickableFindings, !model.areAllSelected(tickableFindings))
                }
                .buttonStyle(SiivOSButtonStyle(.small))
                .help(tr("Ticks everything labelled Safe to remove. Items labelled Check first are left for you to tick one by one."))
            }

            Text(formatBytes(section.totalBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let failure = section.failure {
                Label(tr("This check could not finish: %1$@", failure), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            } else if section.findings.isEmpty {
                Text(tr("Nothing found."))
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(shownFindings) { finding in
                        FindingRow(
                            model: model,
                            finding: finding,
                            showsExplanation: Self.sectionsWithExplanations.contains(section.id),
                            isInSafePart: isSafe
                        )
                    }
                }
                if section.findings.count > Self.rowLimit {
                    Text(tr("Showing the %1$@ largest of %2$@ items.", "\(Self.rowLimit)", "\(section.findings.count)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// One item that could be removed: a tick box, a readable name, and the size.
private struct FindingRow: View {
    @ObservedObject var model: CleanupModel
    let finding: Finding
    let showsExplanation: Bool
    /// True when the row is listed under "Safe to remove". An item there that is
    /// labelled Check first says why, because it differs from its neighbours.
    let isInSafePart: Bool

    var body: some View {
        row
            .help(finding.url.path)
            .contextMenu {
                Button(tr("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([finding.url])
                }
            }
    }

    /// A tick box with the details, or the details alone when the item is held back.
    @ViewBuilder
    private var row: some View {
        if finding.heldBackReason == nil {
            Toggle(isOn: isTicked) {
                details
            }
            .toggleStyle(.checkbox)
        } else {
            details
                .padding(.leading, 22)
        }
    }

    private var details: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.displayName ?? ReadableNames.name(for: finding.url))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsExplanation {
                    Text(finding.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isInSafePart && finding.safety == .checkFirst {
                    Text(finding.safetyReason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let reason = finding.heldBackReason {
                    Label(reason, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            SafetyLabel(safety: finding.safety)
                // Resting the pointer on the label says why the item has it.
                .help(finding.safetyReason)
            Text(sizeText)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                // The same width on every row, so the labels line up in a column.
                .frame(minWidth: 76, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The item's size, or what removing it would free when that is less: a copy that
    /// shares its disk space with a file that stays frees next to nothing.
    private var sizeText: String {
        finding.freesBytes < finding.sizeBytes
            ? tr("frees %1$@", formatBytes(finding.freesBytes))
            : formatBytes(finding.sizeBytes)
    }

    private var isTicked: Binding<Bool> {
        Binding(
            get: { model.isSelected(finding) },
            set: { isOn in model.setSelected(finding, isOn) }
        )
    }
}

/// The label every item carries: "Safe to remove" or "Check first".
///
/// The two are meant to look different at a glance. "Safe to remove" is quiet: a green
/// tick and grey text. "Check first" stands out: the amber mark and amber text.
private struct SafetyLabel: View {
    let safety: Finding.Safety

    var body: some View {
        Group {
            switch safety {
            case .safeToRemove:
                HStack(spacing: 4) {
                    SiivOSIconView(.good, size: 16)
                    Text(safety.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .checkFirst:
                HStack(spacing: 4) {
                    SiivOSIconView(.attention, size: 16)
                    Text(safety.title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(SiivOSIconColors.attention)
                }
            }
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}

/// Explains which kinds of data Cleanup leaves out on purpose.
private struct NeverListedView: View {
    @State private var isOpen = false

    var body: some View {
        DisclosureGroup(tr("What SiivOS never lists here"), isExpanded: $isOpen) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(NeverOffer.Category.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                            .font(.callout)
                            .bold()
                        Text(category.explanation)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
    }
}

/// The bar pinned to the bottom of the window: what is ticked, and the button that removes it.
private struct CleanupActionBar: View {
    @ObservedObject var model: CleanupModel

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selectionSummary)
                    .font(.headline)
                Text(tr("Removed items wait in the holding area. You can put them back from History."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            ProminentButton(tr("Remove Ticked Items…")) {
                model.prepareRemoval()
            }
            .disabled(model.selection.isEmpty || model.isWorking)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        // The window's own green, not the Mac's grey bar material.
        .background(BottomBarBackground())
        .overlay(alignment: .top) {
            ThemedDivider()
        }
    }
}
