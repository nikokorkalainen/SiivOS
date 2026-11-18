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
            self.pendingPlan = plan
        }
    }

    /// Carries out the removal the user has just confirmed, then checks again.
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
            self.check()
        }
    }
}
