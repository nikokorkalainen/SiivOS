import AppKit
import SiivOSCore
import SwiftUI

/// Finds clutter and lets the user choose what to remove.
struct CleanupView: View {
    @ObservedObject var model: CleanupModel

    var body: some View {
        content
            .navigationTitle("Cleanup")
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
        } else if let report = model.report {
            CleanupResultsView(model: model, report: report)
        } else {
            ContentUnavailableView {
                Label("Cleanup", systemImage: "trash")
            } description: {
                Text("SiivOS looks for app caches, logs, leftovers from removed apps, old downloads, large files and duplicate files.")
                Text("Scanning only looks. Nothing is removed until you tick items and confirm. macOS may ask for permission to look in your Desktop, Documents and Downloads folders.")
            } actions: {
                Button("Scan for Clutter") {
                    model.scan()
                }
            }
        }
    }

    private var progressText: String {
        model.scanningTitle.isEmpty ? "Getting ready…" : "Checking: \(model.scanningTitle)…"
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

/// The list of everything a scan found, grouped by kind.
private struct CleanupResultsView: View {
    @ObservedObject var model: CleanupModel
    let report: ScanReport

    @State private var showsNeverOffered = false

    var body: some View {
        Form {
            Section {
                Text("Tick what you want to remove. Removed items go to the holding area, and you can put them back from History.")
                LabeledContent("Ticked", value: selectionText)
                HStack {
                    Button("Remove Ticked Items…") {
                        model.prepareRemoval()
                    }
                    .disabled(model.selection.isEmpty || model.isWorking)
                    Button("Scan Again") {
                        model.scan()
                    }
                    .disabled(model.isWorking)
                }
                .buttonStyle(.bordered)

                DisclosureGroup("What SiivOS never lists here", isExpanded: $showsNeverOffered) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(NeverOffer.Category.allCases, id: \.self) { category in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                    .font(.callout)
                                    .bold()
                                Text(category.explanation)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
            }

            ForEach(report.sections) { section in
                CleanupSectionView(model: model, section: section)
            }
        }
        .formStyle(.grouped)
    }

    private var selectionText: String {
        let count = model.selection.count
        if count == 0 {
            return "Nothing"
        }
        let items = count == 1 ? "1 item" : "\(count) items"
        return "\(items), \(formatBytes(model.selectedBytes))"
    }
}

/// What one kind of check found.
private struct CleanupSectionView: View {
    @ObservedObject var model: CleanupModel
    let section: ScanReport.Section

    /// Long lists are cut off here, largest items first, to keep the screen quick.
    private static let rowLimit = 100

    private var shownFindings: [Finding] {
        Array(section.findings.prefix(Self.rowLimit))
    }

    /// The shown items that can be ticked. Held-back items are left out.
    private var tickableFindings: [Finding] {
        shownFindings.filter { $0.heldBackReason == nil }
    }

    var body: some View {
        Section {
            Text(section.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if let failure = section.failure {
                Label("This check could not finish: \(failure)", systemImage: "exclamationmark.triangle")
            } else if section.findings.isEmpty {
                Text("Nothing found.")
                    .foregroundStyle(.secondary)
            } else {
                Button(model.areAllSelected(tickableFindings) ? "Untick All" : "Tick All") {
                    model.setAllSelected(tickableFindings, !model.areAllSelected(tickableFindings))
                }
                .buttonStyle(.bordered)
                .disabled(tickableFindings.isEmpty)

                ForEach(shownFindings) { finding in
                    FindingRow(model: model, finding: finding)
                }

                if section.findings.count > Self.rowLimit {
                    Text("Showing the \(Self.rowLimit) largest of \(section.findings.count) items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text(section.title)
                Spacer()
                Text(formatBytes(section.totalBytes))
            }
        }
    }
}

/// One item that could be removed, with a tick box.
private struct FindingRow: View {
    @ObservedObject var model: CleanupModel
    let finding: Finding

    var body: some View {
        row
            .contextMenu {
                Button("Show in Finder") {
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
        }
    }

    private var details: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(finding.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let reason = finding.heldBackReason {
                    Label(reason, systemImage: "lock")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text(finding.url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(formatBytes(finding.sizeBytes))
                .foregroundStyle(.secondary)
        }
    }

    private var isTicked: Binding<Bool> {
        Binding(
            get: { model.isSelected(finding) },
            set: { isOn in model.setSelected(finding, isOn) }
        )
    }
}
