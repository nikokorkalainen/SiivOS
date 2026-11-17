import AppKit
import SiivOSCore
import SwiftUI

/// Connects the History screen to the safety core.
@MainActor
final class HistoryModel: ObservableObject {
    /// Every change SiivOS has made, newest first.
    @Published private(set) var records: [ActionRecord] = []
    /// A removal waiting for the user to read its explanation and confirm.
    @Published var pendingPlan: RemovalPlan?
    /// A problem to show the user.
    @Published var message: String?
    /// True while files are being measured or moved.
    @Published private(set) var isWorking = false

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
        reload()
    }

    /// Combined size of everything waiting in the holding area, in bytes.
    var heldBytes: Int64 {
        records.reduce(0) { $0 + $1.heldBytes }
    }

    func reload() {
        guard let core else { return }
        do {
            records = try core.history()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Lets the user pick files or folders, then prepares the explanation for removing them.
    /// Nothing is moved until the user confirms.
    func chooseItemsToRemove() {
        guard let core else { return }

        let panel = NSOpenPanel()
        panel.title = tr("Choose what to remove")
        panel.message = tr("Choose files or folders. You will see what happens before anything is moved.")
        panel.prompt = tr("Continue")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        let urls = panel.urls
        guard !urls.isEmpty else { return }

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(removing: urls, reason: tr("You chose these items yourself."))
            }.value
            self.isWorking = false
            self.pendingPlan = plan
        }
    }

    /// Carries out the removal the user has just confirmed.
    func confirmPendingPlan() {
        guard let plan = pendingPlan else { return }
        pendingPlan = nil
        run { core in
            let result = try core.apply(plan)
            return describe(result.failures, intro: tr("Some items could not be moved and were left where they are:"))
        }
    }

    func putBack(_ record: ActionRecord) {
        let recordID = record.id
        run { core in
            let result = try core.undo(recordID: recordID)
            return describe(result.failures, intro: tr("Some items could not be put back and are still in the holding area:"))
        }
    }

    func deletePermanently(_ record: ActionRecord) {
        let recordID = record.id
        run { core in
            let result = try core.deletePermanently(recordID: recordID)
            return describe(result.failures, intro: tr("Some items could not be deleted and are still in the holding area:"))
        }
    }

    /// Runs file work away from the main thread, then refreshes the list.
    /// The work returns a message to show the user, or `nil` when all went well.
    private func run(_ work: @escaping @Sendable (SafetyCore) throws -> String?) {
        guard let core else { return }
        isWorking = true
        Task {
            let problem = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    return try work(core)
                } catch {
                    return error.localizedDescription
                }
            }.value
            self.isWorking = false
            self.reload()
            if let problem {
                self.message = problem
            }
        }
    }
}
