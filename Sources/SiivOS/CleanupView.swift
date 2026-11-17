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
            ProgressView(progressText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.report != nil {
            CleanupResultsView(model: model)
        } else {
            ContentUnavailableView {
                Label(tr("Cleanup"), systemImage: "trash")
            } description: {
                Text(tr("SiivOS looks for app caches, logs, leftovers from removed apps, old downloads, large files and duplicate files."))
                Text(tr("Scanning only looks. Nothing is removed until you tick items and confirm. macOS may ask for permission to look in your Desktop, Documents and Downloads folders."))
            } actions: {
                Button(tr("Scan for Clutter")) {
                    model.scan()
                }
                .buttonStyle(.borderedProminent)
            }
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
                    Button(tr("Scan Again")) {
                        model.scan()
                    }
                    .disabled(model.isWorking)
                }

                if let notice = model.lastRemoval {
                    RemovalBanner(model: model, notice: notice)
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
            Button(tr("Undo")) {
                model.undoLastRemoval()
            }
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
        .background(Color.siivosLichen.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
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
        "leftovers", "old-downloads", "large-files", "duplicates"
    ]

    private var shownFindings: [Finding] {
        Array(section.findings.prefix(Self.rowLimit))
    }

    /// The shown items that can be ticked. Held-back items are left out.
    private var tickableFindings: [Finding] {
        shownFindings.filter { $0.heldBackReason == nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                details
                    .padding(.top, 10)
                    .padding(.leading, 22)
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
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
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
                .controlSize(.small)
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
                            showsExplanation: Self.sectionsWithExplanations.contains(section.id)
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
                Text(ReadableNames.name(for: finding.url))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if showsExplanation {
                    Text(finding.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = finding.heldBackReason {
                    Label(reason, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(formatBytes(finding.sizeBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isTicked: Binding<Bool> {
        Binding(
            get: { model.isSelected(finding) },
            set: { isOn in model.setSelected(finding, isOn) }
        )
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
            Button(tr("Remove Ticked Items…")) {
                model.prepareRemoval()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.selection.isEmpty || model.isWorking)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
