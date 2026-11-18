import AppKit
import SiivOSCore
import SwiftUI

/// Connects the Apps screen to the app list, the background items and the safety core.
@MainActor
final class AppsModel: ObservableObject {
    enum SortOrder: String, CaseIterable, Identifiable {
        case size
        case name
        case lastUsed

        var id: SortOrder { self }

        var title: String {
            switch self {
            case .size: return tr("Largest first")
            case .name: return tr("Name")
            case .lastUsed: return tr("Longest unused first")
            }
        }
    }

    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var backgroundItems: [BackgroundItem] = []
    /// True once the lists have been read at least once.
    @Published private(set) var hasLoaded = false
    @Published private(set) var isLoading = false
    /// The app being measured right now, shown while loading.
    @Published private(set) var loadingName = ""
    /// True while files are being measured or moved.
    @Published private(set) var isWorking = false
    @Published var sortOrder: SortOrder = .size
    @Published var searchText = ""
    /// A removal waiting for the user to read its explanation and confirm.
    @Published var pendingPlan: RemovalPlan?
    /// A problem to show the user.
    @Published var message: String?

    /// True when the waiting removal is an uninstall, which gets a fuller error message.
    private var pendingPlanIsUninstall = false
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

    // MARK: - Reading

    /// Reads the installed apps and background items. Only looks; nothing is changed.
    func load() {
        guard !isLoading else { return }
        isLoading = true
        loadingName = ""

        Task {
            let loaded = await Task.detached(priority: .userInitiated) { () -> ([AppInfo], [BackgroundItem]) in
                let apps = AppInventory.load { name in
                    Task { @MainActor in
                        self.loadingName = name
                    }
                }
                let items = BackgroundItems.find(in: BackgroundItems.standardDirectories())
                return (apps, items)
            }.value
            self.apps = loaded.0
            self.backgroundItems = loaded.1
            self.isLoading = false
            self.hasLoaded = true
        }
    }

    /// The apps to show: filtered by the search text and put in the chosen order.
    var visibleApps: [AppInfo] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        let matching = query.isEmpty
            ? apps
            : apps.filter { $0.app.name.localizedCaseInsensitiveContains(query) }

        switch sortOrder {
        case .size:
            return matching.sorted { $0.sizeBytes > $1.sizeBytes }
        case .name:
            return matching.sorted {
                $0.app.name.localizedCaseInsensitiveCompare($1.app.name) == .orderedAscending
            }
        case .lastUsed:
            // Apps macOS has no record of are listed first: they have probably never been opened.
            return matching.sorted {
                ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast)
            }
        }
    }

    func backgroundItems(in scope: BackgroundItem.Scope) -> [BackgroundItem] {
        backgroundItems.filter { $0.scope == scope }
    }

    // MARK: - Removing

    /// Prepares the explanation for uninstalling an app together with what it stored.
    /// Nothing is moved until the user confirms.
    func prepareUninstall(_ info: AppInfo) {
        guard let core else { return }
        let app = info.app

        if let identifier = app.bundleIdentifier,
           !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty {
            message = tr("%1$@ is open. Quit it first, then try again.", app.name)
            return
        }

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) { () -> RemovalPlan in
                let related = AppRelatedFiles.find(for: app).map { $0.url }
                return core.plan(
                    removing: [app.url] + related,
                    title: tr("Uninstalled %1$@", app.name),
                    reason: tr("This uninstalls %1$@: the app itself and what it stored in your Library.", app.name),
                    required: [app.url]
                )
            }.value
            self.isWorking = false
            self.pendingPlanIsUninstall = true
            self.pendingPlan = plan
        }
    }

    /// Prepares the explanation for removing a background item of the user's own account.
    func prepareRemoval(of item: BackgroundItem) {
        guard let core else { return }
        let url = item.url
        let label = item.label

        isWorking = true
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                core.plan(
                    removing: [url],
                    title: tr("Removed background item %1$@", label),
                    reason: tr("This stops %1$@ from starting by itself. It takes effect the next time you log in; if it is running now, it keeps running until then.", label)
                )
            }.value
            self.isWorking = false
            self.pendingPlanIsUninstall = false
            self.pendingPlan = plan
        }
    }

    /// Carries out the removal the user has just confirmed.
    func confirmPendingPlan() {
        guard let core, let plan = pendingPlan else { return }
        pendingPlan = nil
        let isUninstall = pendingPlanIsUninstall

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
                    guard isUninstall else {
                        return error.localizedDescription
                    }
                    return tr("The app could not be moved, so nothing was changed.")
                        + "\n\n" + error.localizedDescription + "\n\n"
                        + tr("macOS may be stopping SiivOS from changing apps. In System Settings, open Privacy & Security, then App Management, and allow SiivOS. Apps installed for all users may also need an administrator to remove them.")
                }
            }.value

            // Refresh what is cheap to refresh: drop apps that are gone, and re-read the small settings files.
            self.apps = self.apps.filter { FileManager.default.fileExists(atPath: $0.app.url.path) }
            self.backgroundItems = BackgroundItems.find(in: BackgroundItems.standardDirectories())
            self.isWorking = false
            HoldingStatus.shared.refresh()
            if let problem {
                self.message = problem
            }
        }
    }
}
