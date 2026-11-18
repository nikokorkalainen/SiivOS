import XCTest
@testable import SiivOSCore

final class AppManagerTests: TemporaryDirectoryTestCase {
    private var library: URL {
        home.appendingPathComponent("Library", isDirectory: true)
    }

    private func names(_ items: [RelatedItem]) -> [String] {
        items.map { $0.url.lastPathComponent }.sorted()
    }

    // MARK: - App list

    func testInventoryListsAppsWithVersionAndSize() throws {
        try makeApp("Notes.app", identifier: "com.example.Notes", version: "2.1")
        try makeApp("Utilities/Disk Tool.app", identifier: "org.sample.DiskTool")
        try makeApp("Broken.app", identifier: nil)

        var measured: [String] = []
        let apps = AppInventory.load(directories: [applications]) { measured.append($0) }

        XCTAssertEqual(apps.map { $0.app.name }.sorted(), ["Broken", "Disk Tool", "Notes"])
        XCTAssertEqual(measured.sorted(), ["Broken", "Disk Tool", "Notes"])
        let notes = try XCTUnwrap(apps.first { $0.app.name == "Notes" })
        XCTAssertEqual(notes.app.bundleIdentifier, "com.example.Notes")
        XCTAssertEqual(notes.app.version, "2.1")
        XCTAssertGreaterThanOrEqual(notes.sizeBytes, 10_000)
        XCTAssertFalse(notes.isPartOfMacOS)
        let broken = try XCTUnwrap(apps.first { $0.app.name == "Broken" })
        XCTAssertNil(broken.app.bundleIdentifier)
        XCTAssertNil(broken.app.version)
    }

    // MARK: - What an app stored

    func testRelatedFilesAreFoundByIdentifierAndByExactName() throws {
        let app = try makeApp("Notes.app", identifier: "com.example.Notes")
        try makeFile("Library/Application Support/com.example.Notes/data.db")
        try makeFile("Library/Application Support/Notes/more.db")
        try makeFile("Library/Caches/COM.EXAMPLE.NOTES/cache.bin")
        try makeFile("Library/Logs/Notes/today.log")
        try makeFile("Library/Containers/com.example.Notes/Data/file")
        try makeFile("Library/Preferences/com.example.Notes.plist")
        try makeFile("Library/Preferences/ByHost/com.example.Notes.ABC123.plist")
        try makeFile("Library/Saved Application State/com.example.Notes.savedState/windows.plist")
        try makeFile("Library/Cookies/com.example.Notes.binarycookies")
        try makeFile("Library/LaunchAgents/com.example.Notes.updater.plist")
        // Close, but not this app's.
        try makeFile("Library/Application Support/Notes Helper/data.db")
        try makeFile("Library/Application Support/com.example.NotesPro/data.db")
        try makeFile("Library/Preferences/com.example.NotesPro.plist")
        try makeFile("Library/Preferences/com.example.plist")
        try makeFile("Library/Containers/Notes/Data/file")

        let installed = try XCTUnwrap(InstalledApps.find(in: [applications]).first)
        XCTAssertEqual(installed.url.lastPathComponent, app.lastPathComponent)
        let related = AppRelatedFiles.find(for: installed, homeDirectory: home)

        XCTAssertEqual(names(related), [
            "COM.EXAMPLE.NOTES",
            "Notes",
            "Notes",
            "com.example.Notes",
            "com.example.Notes",
            "com.example.Notes.ABC123.plist",
            "com.example.Notes.binarycookies",
            "com.example.Notes.plist",
            "com.example.Notes.savedState",
            "com.example.Notes.updater.plist"
        ])
        XCTAssertTrue(related.allSatisfy { !$0.kind.isEmpty })
    }

    func testBackgroundItemPointingIntoTheAppCountsAsRelated() throws {
        let app = try makeApp("Notes.app", identifier: "com.example.Notes")
        try writePlist(
            ["Label": "helper", "ProgramArguments": [app.path + "/Contents/MacOS/program", "--background"]],
            to: library.appendingPathComponent("LaunchAgents/some.other.name.plist")
        )
        try writePlist(
            ["Label": "unrelated", "Program": "/usr/bin/true"],
            to: library.appendingPathComponent("LaunchAgents/unrelated.plist")
        )

        let installed = try XCTUnwrap(InstalledApps.find(in: [applications]).first)
        let related = AppRelatedFiles.find(for: installed, homeDirectory: home)

        XCTAssertEqual(names(related), ["some.other.name.plist"])
    }

    func testAppWithoutIdentifierIsMatchedByNameOnly() throws {
        try makeApp("Tool.app", identifier: nil)
        try makeFile("Library/Application Support/Tool/data.db")
        try makeFile("Library/Preferences/Tool.plist")

        let installed = try XCTUnwrap(InstalledApps.find(in: [applications]).first)
        XCTAssertEqual(names(AppRelatedFiles.find(for: installed, homeDirectory: home)), ["Tool"])
    }

    // MARK: - Background items

    func testBackgroundItemsAreReadFromTheirSettingsFiles() throws {
        let agents = library.appendingPathComponent("LaunchAgents", isDirectory: true)
        let daemons = root.appendingPathComponent("LaunchDaemons", isDirectory: true)
        let program = try makeFile("bin/updater")

        try writePlist(
            ["Label": "com.example.updater", "Program": program.path, "RunAtLoad": true],
            to: agents.appendingPathComponent("com.example.updater.plist")
        )
        try writePlist(
            ["Label": "com.gone.helper", "ProgramArguments": ["/no/such/program", "-x"], "KeepAlive": ["Crashed": true]],
            to: agents.appendingPathComponent("com.gone.helper.plist")
        )
        try writePlist(
            ["ProgramArguments": ["relative-program"], "Disabled": true],
            to: daemons.appendingPathComponent("org.sample.daemon.plist")
        )
        try makeFile("Library/LaunchAgents/notes.txt")
        try makeFile("Library/LaunchAgents/damaged.plist", contents: "not a plist")

        let items = BackgroundItems.find(in: [(agents, .user), (daemons, .system), (root.appendingPathComponent("Missing"), .allUsers)])

        XCTAssertEqual(items.map { $0.label }, ["com.example.updater", "com.gone.helper", "org.sample.daemon"])

        let updater = items[0]
        XCTAssertEqual(updater.scope, .user)
        XCTAssertEqual(updater.program, program.path)
        XCTAssertTrue(updater.startsAutomatically)
        XCTAssertTrue(updater.programExists)
        XCTAssertFalse(updater.isDisabled)

        let gone = items[1]
        XCTAssertEqual(gone.program, "/no/such/program")
        XCTAssertTrue(gone.startsAutomatically, "KeepAlive conditions also start the program automatically")
        XCTAssertFalse(gone.programExists)

        let daemon = items[2]
        XCTAssertEqual(daemon.scope, .system)
        XCTAssertFalse(daemon.startsAutomatically)
        XCTAssertTrue(daemon.isDisabled)
        XCTAssertTrue(daemon.programExists, "A program without a full path cannot be checked")
    }

    // MARK: - Uninstalling

    private func makeCore() throws -> SafetyCore {
        try SafetyCore(baseDirectory: baseDirectory, homeDirectory: home)
    }

    func testUninstallMovesTheAppWithItsDataAndUndoBringsItAllBack() throws {
        let app = try makeApp("Notes.app", identifier: "com.example.Notes")
        let data = try makeFile("Library/Application Support/com.example.Notes/data.db", contents: "notes")
        let settings = try makeFile("Library/Preferences/com.example.Notes.plist")
        let installed = try XCTUnwrap(InstalledApps.find(in: [applications]).first)
        let related = AppRelatedFiles.find(for: installed, homeDirectory: home).map { $0.url }

        let core = try makeCore()
        let plan = core.plan(
            removing: related + [app],
            title: "Uninstalled Notes",
            reason: "Test.",
            required: [app]
        )
        XCTAssertEqual(plan.items.count, 3)
        XCTAssertEqual(plan.items[0].url.lastPathComponent, "Notes.app", "The app itself is moved first")
        XCTAssertTrue(plan.items[0].isRequired)
        XCTAssertTrue(plan.refused.isEmpty)

        let result = try core.apply(plan)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertFalse(exists(app))
        XCTAssertFalse(exists(data))
        XCTAssertFalse(exists(settings))
        XCTAssertTrue(InstalledApps.find(in: [applications]).isEmpty)

        let undone = try core.undo(recordID: result.record.id)
        XCTAssertTrue(undone.failures.isEmpty)
        XCTAssertEqual(InstalledApps.find(in: [applications]).first?.bundleIdentifier, "com.example.Notes")
        XCTAssertEqual(try String(contentsOf: data, encoding: .utf8), "notes")
        XCTAssertTrue(exists(settings))
    }

    func testNothingMovesWhenTheRequiredItemCannotBeMoved() throws {
        let app = try makeApp("Notes.app", identifier: "com.example.Notes")
        let data = try makeFile("Library/Application Support/com.example.Notes/data.db")
        let core = try makeCore()
        let plan = core.plan(removing: [data, app], reason: "Test.", required: [app])
        XCTAssertEqual(plan.items.count, 2)
        // The app disappears between the explanation and the confirmation.
        try FileManager.default.removeItem(at: app)

        XCTAssertThrowsError(try core.apply(plan))

        XCTAssertTrue(exists(data))
        XCTAssertEqual(try core.history(), [])
    }

    func testAnOptionalItemFailingDoesNotStopAnUninstall() throws {
        let app = try makeApp("Notes.app", identifier: "com.example.Notes")
        let data = try makeFile("Library/Application Support/com.example.Notes/data.db")
        let core = try makeCore()
        let plan = core.plan(removing: [data, app], reason: "Test.", required: [app])
        try FileManager.default.removeItem(at: data)

        let result = try core.apply(plan)

        XCTAssertFalse(exists(app))
        XCTAssertEqual(result.record.items.count, 1)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testPlanIsEmptyWhenTheRequiredItemIsProtectedOrMissing() throws {
        let data = try makeFile("Library/Application Support/com.example.Notes/data.db")
        let core = try makeCore()

        let missingApp = applications.appendingPathComponent("Gone.app", isDirectory: true)
        let missingPlan = core.plan(removing: [data, missingApp], reason: "Test.", required: [missingApp])
        XCTAssertTrue(missingPlan.items.isEmpty)
        XCTAssertEqual(missingPlan.refused.count, 1)

        let system = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        let systemPlan = core.plan(removing: [data, system], reason: "Test.", required: [system])
        XCTAssertTrue(systemPlan.items.isEmpty)
        XCTAssertTrue(exists(data))
    }
}
