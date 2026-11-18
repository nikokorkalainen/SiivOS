import AppKit
import SiivOSCore
import SwiftUI

/// Connects the Protection screen to the protection checks and the safety core.
@MainActor
final class ProtectionModel: ObservableObject {
    /// What the last check found, or `nil` before the first check.
    @Published private(set) var report: ProtectionReport?
    @Published private(set) var isChecking = false
    /// The check that is running right now, shown while checking.
    @Published private(set) var checkingTitle = ""
    /// True while a file is being measured or moved.
    @Published private(set) var isWorking = false
    /// A removal waiting for the user to read its explanation and confirm.
    @Published var pendingPlan: RemovalPlan?
    /// A problem to show the user.
    @Published var message: String?

    /// What the malware scanner is doing right now.
    enum ScannerActivity: Equatable {
        case idle
        case updating
        /// Scanning, with the name of the place being scanned.
        case scanning(String)
    }

    /// The ClamAV found on this Mac, or `nil` when it is not installed.
    @Published private(set) var scanner: ClamAVStatus?
    /// True once SiivOS has looked for ClamAV at least once.
    @Published private(set) var hasLookedForScanner = false
    @Published private(set) var scannerActivity: ScannerActivity = .idle
    /// How the last malware scan went, and where it looked.
    @Published private(set) var lastScan: MalwareScanResult?
    @Published private(set) var lastScanPlace = ""

    /// True when the waiting removal is a file ClamAV detected, not a background item.
    private var pendingPlanIsDetection = false
    private let clamAV = ClamAV.standard()
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

    /// Looks at the Mac's protection. Checking only reads; nothing is changed.
    func check() {
        guard !isChecking else { return }
        isChecking = true
        checkingTitle = ""

        Task {
            let newReport = await Task.detached(priority: .userInitiated) {
                ProtectionCheck.run { title in
                    Task { @MainActor in
                        self.checkingTitle = title
                    }
                }
            }.value
            self.report = newReport
            self.isChecking = false
        }
    }

    /// Prepares the explanation for removing a background item of the user's own account.
    /// Nothing is moved until the user confirms.
    func prepareRemoval(of finding: ProtectionFinding) {
        guard let core, finding.canRemove, let url = finding.fileURL else { return }
        let name = finding.title

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(
                    removing: [url],
                    title: tr("Removed background item %1$@", name),
                    reason: tr("This stops %1$@ from starting by itself. It takes effect the next time you log in; if it is running now, it keeps running until then.", name)
                )
            }.value
            self.isWorking = false
            self.pendingPlanIsDetection = false
            self.pendingPlan = plan
        }
    }

    // MARK: - Malware scan

    /// Looks for ClamAV and its definitions. Only reads.
    func refreshScanner() {
        let clamAV = self.clamAV
        Task {
            let status = await Task.detached(priority: .userInitiated) {
                clamAV.status()
            }.value
            self.scanner = status
            self.hasLookedForScanner = true
        }
    }

    /// Downloads ClamAV's virus definitions. This is the one thing in SiivOS that uses the
    /// network, and it only runs because the user clicked the button for it.
    func updateDefinitions() {
        guard scannerActivity == .idle else { return }
        scannerActivity = .updating
        let clamAV = self.clamAV
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> (String?, ClamAVStatus?) in
                let problem = clamAV.updateDefinitions()
                return (problem, clamAV.status())
            }.value
            self.scanner = outcome.1
            self.scannerActivity = .idle
            if let problem = outcome.0 {
                self.message = problem
            }
        }
    }

    func scanDownloads() {
        let downloads = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads", isDirectory: true)
        scan([downloads], place: tr("Downloads"))
    }

    /// Lets the user pick files or folders, then scans them.
    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose what to scan")
        panel.prompt = tr("Scan")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        let place = panel.urls.count == 1
            ? first.lastPathComponent
            : tr("%1$@ items", "\(panel.urls.count)")
        scan(panel.urls, place: place)
    }

    private func scan(_ urls: [URL], place: String) {
        guard scannerActivity == .idle else { return }
        scannerActivity = .scanning(place)
        lastScan = nil
        let clamAV = self.clamAV
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                clamAV.scan(urls)
            }.value
            self.lastScan = result
            self.lastScanPlace = place
            self.scannerActivity = .idle
            if let problem = result.problem {
                self.message = problem
            }
        }
    }

    /// Stops the scan or download that is running.
    func stopScanner() {
        clamAV.cancel()
    }

    /// Prepares the explanation for removing a file ClamAV detected. Nothing is moved
    /// until the user confirms, and the file goes to the holding area, not the bin.
    func prepareRemoval(of detection: MalwareDetection) {
        guard let core else { return }
        let url = detection.url
        let name = detection.name

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(
                    removing: [url],
                    reason: tr("ClamAV identifies this file as %1$@.", name)
                )
            }.value
            self.isWorking = false
            self.pendingPlanIsDetection = true
            self.pendingPlan = plan
        }
    }

    /// Carries out the removal the user has just confirmed, then brings the lists up to date.
    func confirmPendingPlan() {
        guard let core, let plan = pendingPlan else { return }
        pendingPlan = nil
        let wasDetection = pendingPlanIsDetection

        isWorking = true
        Task {
            let problem = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    let result = try core.apply(plan)
                    return describe(
                        result.failures,
                        intro: tr("Some items could not be moved and were left where they are:")
                    )
                } catch {
                    return error.localizedDescription
                }
            }.value
            self.isWorking = false
            HoldingStatus.shared.refresh()
            if let problem {
                self.message = problem
            }
            if wasDetection {
                self.lastScan = self.lastScan?.removingDetectionsNoLongerOnDisk()
            } else {
                self.check()
            }
        }
    }
}
