import AppKit
import SiivOSCore
import SwiftUI

/// Shows what protects this Mac and what on it deserves a look. Checking only reads;
/// the one thing that can be removed here, a background item of the user's own, goes
/// through the usual explanation and the holding area.
struct ProtectionView: View {
    @ObservedObject var model: ProtectionModel

    var body: some View {
        content
            .navigationTitle(tr("Protection"))
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
        if model.isChecking {
            LoadingView(text: progressText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let report = model.report {
            ProtectionResultsView(model: model, report: report)
        } else {
            startScreen
        }
    }

    /// The screen before the first check, in the open layout.
    private var startScreen: some View {
        CenteredScreen {
            SiivOSIconView(.protection, size: 72)
            Text(tr("Check this Mac's protection"))
                .font(.system(size: 22, weight: .semibold))
            VStack(spacing: 6) {
                Text(tr("SiivOS looks at the protection built into macOS, at what starts by itself, at browser extensions, at configuration profiles and at which apps hold which permissions."))
                Text(tr("Checking only looks. Nothing is changed."))
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 500)
            .fixedSize(horizontal: false, vertical: true)

            ProminentButton(tr("Check Protection")) {
                model.check()
            }
            .padding(.top, 4)
        }
    }

    private var progressText: String {
        model.checkingTitle.isEmpty ? tr("Getting ready…") : tr("Checking: %1$@…", model.checkingTitle)
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

/// Everything a check found: one summary, then a panel per kind of check.
private struct ProtectionResultsView: View {
    @ObservedObject var model: ProtectionModel
    let report: ProtectionReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    title: tr("Protection"),
                    subtitle: tr("What protects this Mac, and what on it deserves a look.")
                ) {
                    Button {
                        model.check()
                    } label: {
                        ButtonLabel(title: tr("Check Again"), systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(SiivOSButtonStyle(.standard))
                    .disabled(model.isWorking)
                }

                summary

                ForEach(report.sections) { section in
                    ProtectionSectionView(model: model, section: section)
                }
            }
            .padding(24)
            .readableWidth()
        }
    }

    /// One calm sentence on how the whole check went.
    private var summary: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                SiivOSIconView(icon(for: report.overallLevel), size: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(summaryTitle)
                        .font(.headline)
                    Text(summaryText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr("SiivOS does not scan files for viruses here. macOS's built-in protection does that in the background."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var summaryTitle: String {
        let attention = report.count(of: .attention)
        if attention == 1 {
            return tr("1 thing needs a closer look")
        }
        if attention > 1 {
            return tr("%1$@ things need a closer look", "\(attention)")
        }
        if report.count(of: .note) > 0 {
            return tr("Nothing alarming")
        }
        return tr("Nothing unusual found")
    }

    private var summaryText: String {
        if report.count(of: .attention) > 0 {
            return tr("They are marked below. Each says why it stands out, so you can decide whether you recognise it.")
        }
        let notes = report.count(of: .note)
        if notes == 1 {
            return tr("1 thing is worth knowing about. It is often perfectly normal.")
        }
        if notes > 1 {
            return tr("%1$@ things are worth knowing about. They are often perfectly normal.", "\(notes)")
        }
        return tr("SiivOS looked at everything listed below and none of it stands out.")
    }
}

/// What one kind of check found, as a panel.
private struct ProtectionSectionView: View {
    @ObservedObject var model: ProtectionModel
    let section: ProtectionSection

    @State private var showsTheRest = false

    /// These checks are short lists where every line is worth reading, so nothing is tucked away.
    private var showsEverything: Bool {
        section.id == "macos" || section.id == "permissions"
    }

    private var shown: [ProtectionFinding] {
        showsEverything ? section.findings : section.noteworthy
    }

    private var tuckedAway: [ProtectionFinding] {
        showsEverything ? [] : section.unremarkable
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.headline)
                    Text(section.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let reason = section.unavailableReason {
                    ThemedDivider()
                    Text(reason)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tr("Open Privacy & Security Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                } else if section.findings.isEmpty {
                    ThemedDivider()
                    Text(tr("Nothing found."))
                        .foregroundStyle(.secondary)
                }

                ForEach(shown) { finding in
                    ThemedDivider()
                    ProtectionFindingRow(model: model, finding: finding)
                }

                if !tuckedAway.isEmpty {
                    ThemedDivider()
                    Button {
                        showsTheRest.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            DisclosureArrow(isOpen: showsTheRest)
                            Text(restTitle)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if showsTheRest {
                        ForEach(tuckedAway) { finding in
                            ProtectionFindingRow(model: model, finding: finding)
                                .padding(.leading, 26)
                        }
                    }
                }
            }
        }
    }

    private var restTitle: String {
        let count = tuckedAway.count
        if shown.isEmpty {
            return count == 1 ? tr("1 item, nothing unusual") : tr("%1$@ items, nothing unusual", "\(count)")
        }
        return count == 1 ? tr("1 more, nothing unusual") : tr("%1$@ more, nothing unusual", "\(count)")
    }
}

/// One thing the check looked at: what it is, what SiivOS makes of it, and what can be done.
private struct ProtectionFindingRow: View {
    @ObservedObject var model: ProtectionModel
    let finding: ProtectionFinding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SiivOSIconView(icon(for: finding.level), size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(finding.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = finding.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            Spacer()
            if finding.level != .fine {
                if finding.canRemove {
                    Button(tr("Remove…")) {
                        model.prepareRemoval(of: finding)
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                    .disabled(model.isWorking)
                } else if let url = finding.fileURL {
                    Button(tr("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                }
            }
        }
        .contextMenu {
            if let url = finding.fileURL {
                Button(tr("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
        }
    }
}

/// The notice icon for a level: a check, an "i", or an exclamation mark in calm amber.
private func icon(for level: ProtectionFinding.Level) -> SiivOSIcon {
    switch level {
    case .fine: return .good
    case .note: return .note
    case .attention: return .attention
    }
}
