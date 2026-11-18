import AppKit
import SiivOSCore
import SwiftUI

/// What the last removal did, shown in a banner with an Undo button.
struct RemovalNotice: Equatable, Sendable {
    let recordID: UUID
    let itemCount: Int
    let bytes: Int64
}

/// Connects the Overview and Cleanup screens to the scan engine and the safety core.
@MainActor
final class CleanupModel: ObservableObject {
    /// The checks whose findings apps and macOS made for themselves. The other checks
    /// find the user's own files, which are looked at one by one.
    static let safeSectionIDs: Set<String> = ["caches", "logs", "leftovers", "developer"]

    /// What the last scan found, or `nil` before the first scan.
    @Published private(set) var report: ScanReport?
    /// When the last scan finished.
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var isScanning = false
    /// The check that is running right now, shown while scanning.
    @Published private(set) var scanningTitle = ""
    /// True while files are being measured or moved.
    @Published private(set) var isWorking = false
    /// The items the user has ticked.
    @Published private(set) var selection: Set<URL> = []
    /// The removal that has just been carried out, until the user hides it or scans again.
    @Published private(set) var lastRemoval: RemovalNotice?
    /// A removal waiting for the user to read its explanation and confirm.
    @Published var pendingPlan: RemovalPlan?
    /// A problem to show the user.
    @Published var message: String?

    /// The findings as they were before the last removal, so Undo can bring the list back.
    private var reportBeforeRemoval: ScanReport?
    private let core: SafetyCore?

    init() {
        var startupProblem: String?
        switch AppCore.shared {
        case .success(let sharedCore):
            core = sharedCore
        case .failure(let error):
            core = nil
            startupProblem = tr("SiivOS could not set up its holding area: %1$@", error.localizedDescription)
        }
        message = startupProblem
    }

    // MARK: - Scanning

    /// Looks for clutter. Scanning only reads; nothing is changed.
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanningTitle = ""
        selection = []
        lastRemoval = nil
        reportBeforeRemoval = nil

        // The apps that are open now. Their caches and logs are listed but cannot be ticked.
        let openApps = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard let name = app.localizedName else { return nil }
            return RunningApp(name: name, bundleIdentifier: app.bundleIdentifier)
        }

        Task {
            let newReport = await Task.detached(priority: .userInitiated) {
                ScanEngine.clutter(runningApps: openApps).run { title in
                    Task { @MainActor in
                        self.scanningTitle = title
                    }
                }
            }.value
            self.report = newReport
            self.lastScanDate = Date()
            self.isScanning = false
        }
    }

    // MARK: - What was found

    /// The groups whose findings apps and macOS made for themselves.
    ///
    /// The developer tools group is left out when it found nothing, because most people
    /// have no such tools and an empty group would only be in the way.
    var safeSections: [ScanReport.Section] {
        (report?.sections ?? []).filter { section in
            guard Self.safeSectionIDs.contains(section.id) else {
                return false
            }
            return section.id != "developer" || !section.findings.isEmpty || section.failure != nil
        }
    }

    /// The groups whose findings are the user's own files.
    var checkFirstSections: [ScanReport.Section] {
        report?.sections.filter { !Self.safeSectionIDs.contains($0.id) } ?? []
    }

    /// Combined size of everything labelled Safe to remove that can be removed right
    /// now. Items labelled Check first are not counted, wherever they are listed.
    var safeToRemoveBytes: Int64 {
        report?.safeToRemoveBytes ?? 0
    }

    /// How many of the user's own files were found. A file listed under two headings counts once.
    var ownFilesCount: Int {
        Set(checkFirstSections.flatMap { $0.findings }.map { $0.url }).count
    }

    // MARK: - Selecting

    func isSelected(_ finding: Finding) -> Bool {
        selection.contains(finding.url)
    }

    func setSelected(_ finding: Finding, _ isOn: Bool) {
        // An item that is held back, for example because its app is open, cannot be ticked.
        guard finding.heldBackReason == nil else { return }
        if isOn {
            selection.insert(finding.url)
        } else {
            selection.remove(finding.url)
        }
    }

    func areAllSelected(_ findings: [Finding]) -> Bool {
        !findings.isEmpty && findings.allSatisfy { selection.contains($0.url) }
    }

    func setAllSelected(_ findings: [Finding], _ isOn: Bool) {
        for finding in findings {
            setSelected(finding, isOn)
        }
    }

    /// Combined size of the ticked items. An item listed under two headings is counted once.
    var selectedBytes: Int64 {
        guard let report else { return 0 }
        var counted = Set<URL>()
        var total: Int64 = 0
        for section in report.sections {
            for finding in section.findings where selection.contains(finding.url) {
                if counted.insert(finding.url).inserted {
                    total += finding.sizeBytes
                }
            }
        }
        return total
    }

    /// What is ticked, in a few words, for the bar at the bottom of the Cleanup screen.
    var selectionSummary: String {
        let count = selection.count
        if count == 0 {
            return tr("Nothing ticked")
        }
        let size = formatBytes(selectedBytes)
        return count == 1
            ? tr("1 item ticked, %1$@", size)
            : tr("%1$@ items ticked, %2$@", "\(count)", size)
    }

    // MARK: - Removing

    /// Prepares the explanation for removing the ticked items. Nothing is moved until the user confirms.
    func prepareRemoval() {
        guard let core, !selection.isEmpty else { return }
        let urls = Array(selection)

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(removing: urls)
            }.value
            self.isWorking = false
            self.pendingPlan = plan
        }
    }

    /// Carries out the removal the user has just confirmed.
    func confirmPendingPlan() {
        guard let core, let plan = pendingPlan else { return }
        pendingPlan = nil

        isWorking = true
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> ApplyOutcome in
                do {
                    let result = try core.apply(plan)
                    let notice = RemovalNotice(
                        recordID: result.record.id,
                        itemCount: result.record.items.count,
                        bytes: result.record.totalBytes
                    )
                    let problem = describe(
                        result.failures,
                        intro: tr("Some items could not be moved and were left where they are:")
                    )
                    return ApplyOutcome(notice: notice, problem: problem)
                } catch {
                    return ApplyOutcome(notice: nil, problem: error.localizedDescription)
                }
            }.value

            // Drop what is gone from the list, and keep only ticks for items that are still listed.
            if let currentReport = self.report {
                let updated = currentReport.removingFindingsNoLongerOnDisk()
                let remaining = Set(updated.sections.flatMap { $0.findings }.map { $0.url })
                if outcome.notice != nil {
                    self.reportBeforeRemoval = currentReport
                }
                self.report = updated
                self.selection = self.selection.intersection(remaining)
            }
            if let notice = outcome.notice {
                self.lastRemoval = notice
            }
            self.isWorking = false
            HoldingStatus.shared.refresh()
            if let problem = outcome.problem {
                self.message = problem
            }
        }
    }

    /// Puts back what the last removal moved, and brings those items back into the list.
    func undoLastRemoval() {
        guard let core, let notice = lastRemoval else { return }

        isWorking = true
        Task {
            let problem = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    let result = try core.undo(recordID: notice.recordID)
                    return describe(
                        result.failures,
                        intro: tr("Some items could not be put back and are still in the holding area:")
                    )
                } catch {
                    return error.localizedDescription
                }
            }.value

            if let earlierReport = self.reportBeforeRemoval {
                self.report = earlierReport.removingFindingsNoLongerOnDisk()
            }
            self.reportBeforeRemoval = nil
            self.lastRemoval = nil
            self.isWorking = false
            HoldingStatus.shared.refresh()
            if let problem {
                self.message = problem
            }
        }
    }

    /// Hides the banner about the last removal. The removal itself stays in History.
    func dismissRemovalNotice() {
        lastRemoval = nil
        reportBeforeRemoval = nil
    }
}

/// What applying a plan led to, carried back from the background.
private struct ApplyOutcome: Sendable {
    let notice: RemovalNotice?
    let problem: String?
}
