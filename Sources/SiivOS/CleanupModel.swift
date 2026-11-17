import SiivOSCore
import SwiftUI

/// Connects the Cleanup screen to the scan engine and the safety core.
@MainActor
final class CleanupModel: ObservableObject {
    /// What the last scan found, or `nil` before the first scan.
    @Published private(set) var report: ScanReport?
    @Published private(set) var isScanning = false
    /// The check that is running right now, shown while scanning.
    @Published private(set) var scanningTitle = ""
    /// True while files are being measured or moved.
    @Published private(set) var isWorking = false
    /// The items the user has ticked.
    @Published private(set) var selection: Set<URL> = []
    /// A removal waiting for the user to read its explanation and confirm.
    @Published var pendingPlan: RemovalPlan?
    /// A problem to show the user.
    @Published var message: String?

    private let core: SafetyCore?

    init() {
        var startupProblem: String?
        switch AppCore.shared {
        case .success(let sharedCore):
            core = sharedCore
        case .failure(let error):
            core = nil
            startupProblem = "SiivOS could not set up its holding area: \(error.localizedDescription)"
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

        Task {
            let newReport = await Task.detached(priority: .userInitiated) {
                ScanEngine.clutter().run { title in
                    Task { @MainActor in
                        self.scanningTitle = title
                    }
                }
            }.value
            self.report = newReport
            self.isScanning = false
        }
    }

    // MARK: - Selecting

    func isSelected(_ finding: Finding) -> Bool {
        selection.contains(finding.url)
    }

    func setSelected(_ finding: Finding, _ isOn: Bool) {
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

    // MARK: - Removing

    /// Prepares the explanation for removing the ticked items. Nothing is moved until the user confirms.
    func prepareRemoval() {
        guard let core, !selection.isEmpty else { return }
        let urls = Array(selection)

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(removing: urls, reason: "You selected these items in Cleanup.")
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
            let problem = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    let result = try core.apply(plan)
                    return describe(
                        result.failures,
                        intro: "Some items could not be moved and were left where they are:"
                    )
                } catch {
                    return error.localizedDescription
                }
            }.value

            // Drop what is gone from the list, and keep only ticks for items that are still listed.
            if let currentReport = self.report {
                let updated = currentReport.removingFindingsNoLongerOnDisk()
                let remaining = Set(updated.sections.flatMap { $0.findings }.map { $0.url })
                self.report = updated
                self.selection = self.selection.intersection(remaining)
            }
            self.isWorking = false
            if let problem {
                self.message = problem
            }
        }
    }
}
