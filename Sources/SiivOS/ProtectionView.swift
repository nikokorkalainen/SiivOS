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
            .onAppear {
                model.refreshScanner()
            }
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

                MalwareScanPanel(model: model)

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

/// Scanning files for malware with a ClamAV the user installed themselves. Says plainly
/// when ClamAV is missing, when it needs to download something, and what a scan found.
private struct MalwareScanPanel: View {
    @ObservedObject var model: ProtectionModel

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("Malware scan"))
                        .font(.headline)
                    Text(tr("Scans files for known malware with ClamAV, free software that you install yourself. macOS's own protection keeps working either way; this is a second opinion."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ThemedDivider()

                if !model.hasLookedForScanner {
                    Text(tr("Looking for ClamAV…"))
                        .foregroundStyle(.secondary)
                } else if let scanner = model.scanner {
                    installed(scanner)
                } else {
                    notInstalled
                }

                if let result = model.lastScan, model.scannerActivity == .idle {
                    ThemedDivider()
                    scanResult(result)
                }
            }
        }
    }

    // MARK: Not installed

    private var notInstalled: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(tr("ClamAV is not installed on this Mac. To add it:"))
            Text(tr("1. Install Homebrew, a free tool for installing software, from brew.sh."))
            Text(tr("2. Open Terminal and run: brew install clamav"))
            Text(tr("3. Come back here and click Look Again."))
            HStack {
                Button(tr("Open brew.sh")) {
                    if let url = URL(string: "https://brew.sh") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(tr("Copy the Command")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("brew install clamav", forType: .string)
                }
                Button(tr("Look Again")) {
                    model.refreshScanner()
                }
            }
            .buttonStyle(SiivOSButtonStyle(.small))
            .padding(.top, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Installed

    @ViewBuilder
    private func installed(_ scanner: ClamAVStatus) -> some View {
        Text(tr("ClamAV %1$@ is installed.", scanner.engineVersion ?? ""))

        switch model.scannerActivity {
        case .updating:
            busy(tr("Downloading definitions. This can take a few minutes…"))
        case .scanning(let place):
            busy(tr("Scanning %1$@. ClamAV first loads its definitions, which takes about half a minute, and a large folder can take much longer.", place))
        case .idle:
            if scanner.hasDefinitions {
                Text(definitionsText(scanner))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(tr("Scan Downloads")) {
                        model.scanDownloads()
                    }
                    Button(tr("Scan a Folder…")) {
                        model.chooseFolderAndScan()
                    }
                    Button(tr("Update Definitions")) {
                        model.updateDefinitions()
                    }
                    .disabled(scanner.updaterPath == nil)
                }
                .buttonStyle(SiivOSButtonStyle(.small))
            } else {
                Text(tr("Before it can scan, ClamAV needs its list of known malware."))
                Button(tr("Download Definitions")) {
                    model.updateDefinitions()
                }
                .buttonStyle(SiivOSButtonStyle(.small))
                .disabled(scanner.updaterPath == nil)
            }
            Text(tr("Downloading or updating definitions connects to ClamAV's servers (database.clamav.net) and stores a few hundred megabytes in SiivOS's own folder. SiivOS uses the network for nothing else."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A line of progress with the small loading animation and a way to stop.
    private func busy(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            GlintLoader(size: 20)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(tr("Stop")) {
                model.stopScanner()
            }
            .buttonStyle(SiivOSButtonStyle(.small))
        }
    }

    private func definitionsText(_ scanner: ClamAVStatus) -> String {
        guard let date = scanner.definitionsDate else {
            return tr("Its definitions are downloaded.")
        }
        let when = date.formatted(date: .abbreviated, time: .omitted)
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days > 7 {
            return tr("Its definitions are from %1$@, %2$@ days ago. Update them before scanning, so that newer malware is recognised.", when, "\(days)")
        }
        return tr("Its definitions are from %1$@.", when)
    }

    // MARK: Result

    @ViewBuilder
    private func scanResult(_ result: MalwareScanResult) -> some View {
        if result.wasCancelled {
            Text(tr("The scan was stopped before it finished."))
                .foregroundStyle(.secondary)
        } else if let problem = result.problem {
            Text(problem)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if result.detections.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                SiivOSIconView(.good, size: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Nothing found in %1$@.", model.lastScanPlace))
                    if let count = result.scannedFiles {
                        Text(tr("%1$@ files were scanned.", "\(count)"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else {
            ForEach(result.detections) { detection in
                HStack(alignment: .top, spacing: 12) {
                    SiivOSIconView(.attention, size: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detection.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(tr("ClamAV identifies this as %1$@. Detections are sometimes wrong, so SiivOS moves the file to the holding area instead of deleting it, and you can put it back.", detection.name))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(detection.path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Button(tr("Remove…")) {
                        model.prepareRemoval(of: detection)
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                    .disabled(model.isWorking)
                }
                .contextMenu {
                    Button(tr("Show in Finder")) {
                        NSWorkspace.shared.activateFileViewerSelecting([detection.url])
                    }
                }
            }
        }
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
