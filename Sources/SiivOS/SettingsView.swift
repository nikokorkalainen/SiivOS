import AppKit
import SiivOSCore
import SwiftUI

/// Settings, as a screen in the main window: one scrolling page with a heading for each
/// group. Laid out as the "Settings" section of docs/design.md describes, with the
/// building blocks from SiivOSSettingsControls.swift.
struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                PageHeader(
                    title: tr("Settings"),
                    subtitle: tr("How SiivOS runs, and what Cleanup lists.")
                ) {
                    EmptyView()
                }

                GeneralSettingsGroup()
                CleanupSettingsGroup()
                HoldingAreaSettingsGroup()
                PermissionsSettingsGroup()
                AgentSettingsGroup()
                PrivacyGroup()
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(tr("Settings"))
    }
}

// MARK: - Shared pieces

/// A group of settings: a heading, then its panels.
private struct SettingsGroup<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            content
        }
    }
}

/// A smaller heading over a panel inside a group.
private struct SettingsSubheading: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold))
            .padding(.top, 6)
    }
}

/// A panel of rows. Rows bring their own padding, and dividers go between them.
private struct SettingsPanel<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }
}

/// The Mac's own switch in the theme's colour. The title is hidden on screen, where the
/// row's label shows it, and still read by VoiceOver.
private struct SettingSwitch: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(SiivOSTheme.prominent)
    }
}

// MARK: - General

private struct GeneralSettingsGroup: View {
    @AppStorage(AppSettings.showsMenuBarKey) private var showsMenuBar = true
    /// What macOS says about opening SiivOS at login. Looked up when the screen is shown
    /// and when SiivOS comes forward again, since it can also be changed in System Settings.
    @State private var loginItem = LoginItem.status
    /// Why opening at login could not be changed, if it could not.
    @State private var loginProblem: String?
    @ObservedObject private var notifier = ChangeNotifier.shared

    var body: some View {
        SettingsGroup(tr("General")) {
            SettingsPanel {
                SettingRow(
                    tr("Show SiivOS in the menu bar"),
                    notes: [tr("With this on, SiivOS stays in the menu bar after you close its window, shows the health score there and takes a reading every six hours. It is in the Dock only while its window is open. To stop it, choose Quit SiivOS in the menu bar or press Command-Q.")]
                ) {
                    SettingSwitch(title: tr("Show SiivOS in the menu bar"), isOn: $showsMenuBar)
                }
                ThemedDivider()
                SettingRow(tr("Open SiivOS at login"), notes: loginNotes) {
                    SettingSwitch(title: tr("Open SiivOS at login"), isOn: opensAtLogin)
                        .disabled(loginItem == .unavailable)
                }
                if loginItem == .needsApproval {
                    Button(tr("Open Login Items Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                if let loginProblem {
                    SettingErrorLine(reason: loginProblem)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
                ThemedDivider()
                SettingRow(tr("Notify me about changes worth a look"), notes: notificationNotes) {
                    SettingSwitch(title: tr("Notify me about changes worth a look"), isOn: notifiesAboutChanges)
                        .disabled(notifier.permission == .unavailable)
                }
                if notifier.isOn && notifier.permission == .denied {
                    Button(tr("Open Notifications Settings")) {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
                ThemedDivider()
                SettingRow(tr("Welcome")) {
                    Button(tr("Show Again")) {
                        AppNavigation.shared.showsWelcome = true
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                }
            }
        }
        .onAppear {
            loginItem = LoginItem.status
            notifier.refreshPermission()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = LoginItem.status
            notifier.refreshPermission()
        }
    }

    /// What the notifications are about, and anything standing in their way right now.
    private var notificationNotes: [String] {
        var notes = [
            tr("SiivOS shows a notification when it notices something new that starts by itself, a new configuration profile, or one of macOS's protections turned off. A click on it opens the Health Timeline. The notification is made on this Mac and sent nowhere."),
            tr("SiivOS only notices while it is running: it looks for new background items every half hour, and for the rest when it takes a reading. With the menu bar icon and Open SiivOS at login it runs all day.")
        ]
        switch notifier.permission {
        case .denied where notifier.isOn:
            notes.append(tr("macOS is not letting SiivOS show notifications. Open Notifications in System Settings and allow SiivOS there."))
        case .unavailable:
            notes.append(tr("This works in the app built with Scripts/make-app.sh. This copy of SiivOS was started another way, so it cannot show notifications."))
        default:
            break
        }
        return notes
    }

    private var notifiesAboutChanges: Binding<Bool> {
        Binding(
            get: { notifier.isOn },
            set: { isOn in notifier.setOn(isOn) }
        )
    }

    /// What the switch does, and anything the user has to know about its state right now.
    private var loginNotes: [String] {
        var notes = [tr("SiivOS starts by itself when you log in to this Mac. If it is shown in the menu bar, it starts there quietly, without opening its window.")]
        switch loginItem {
        case .needsApproval:
            notes.append(tr("macOS wants you to allow this first: open Login Items in System Settings and switch SiivOS on there."))
        case .unavailable:
            notes.append(tr("This works in the app built with Scripts/make-app.sh. This copy of SiivOS was started another way, so macOS cannot open it at login."))
        case .on, .off:
            break
        }
        return notes
    }

    /// Asks macOS to open SiivOS at login, or to stop. The switch then shows what macOS
    /// says, which is the truth even if the change did not go through.
    private var opensAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem == .on || loginItem == .needsApproval },
            set: { isOn in
                do {
                    try LoginItem.set(isOn)
                    loginProblem = nil
                } catch {
                    loginProblem = error.localizedDescription
                }
                loginItem = LoginItem.status
            }
        )
    }
}

// MARK: - Cleanup

/// One check in the list of checks to run.
private struct CheckChoice: Identifiable {
    let id: String
    let title: String
}

/// What Cleanup looks for: how old, how large, which checks, and folders to leave out.
/// The settings are kept in a file in SiivOS's own folder, so that the tool for AI
/// agents scans the same way as the app.
private struct CleanupSettingsGroup: View {
    @State private var settings = CleanupSettingsStore.standard().load()
    /// Why the settings could not be saved, if they could not.
    @State private var problem: String?

    private let checks = ScanEngine.clutterChecks.map { CheckChoice(id: $0.id, title: $0.title) }

    var body: some View {
        SettingsGroup(tr("Cleanup")) {
            SettingsPanel {
                SettingRow(tr("A download counts as old after")) {
                    SiivOSMenuPicker(
                        title: tr("A download counts as old after"),
                        selection: $settings.oldDownloadDays,
                        options: CleanupSettings.oldDownloadChoices.map { ($0, ageText($0)) }
                    )
                }
                ThemedDivider()
                SettingRow(tr("A file counts as large from")) {
                    SiivOSMenuPicker(
                        title: tr("A file counts as large from"),
                        selection: $settings.largeFileBytes,
                        options: CleanupSettings.largeFileChoices.map { ($0, formatBytes($0)) }
                    )
                }
                if let problem {
                    ThemedDivider()
                    SettingErrorLine(reason: problem)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }

            SettingsSubheading(title: tr("Checks to run"))
            SettingsPanel {
                ForEach(checks) { check in
                    if check.id != checks.first?.id {
                        ThemedDivider()
                    }
                    SettingRow(check.title) {
                        SettingSwitch(title: check.title, isOn: runs(check.id))
                    }
                }
            }

            SettingsSubheading(title: tr("Folders to leave out"))
            SettingsPanel {
                SettingNoteText(tr("Nothing in these folders is listed in Cleanup, whichever check would have found it. The folders themselves are not touched."))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                ThemedDivider()
                if settings.foldersLeftOut.isEmpty {
                    Text(tr("No folders are left out."))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                } else {
                    ForEach(settings.foldersLeftOut, id: \.self) { path in
                        FolderRow(path: path) {
                            settings.foldersLeftOut.removeAll { $0 == path }
                        }
                        ThemedDivider()
                    }
                }
                if settings.foldersLeftOut.isEmpty {
                    ThemedDivider()
                }
                Button(tr("Add Folder…")) {
                    addFolders()
                }
                .buttonStyle(SiivOSButtonStyle(.small))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }

            SettingNoteText(tr("Changes apply the next time you scan."))
        }
        .onChange(of: settings) { _, newSettings in
            do {
                try CleanupSettingsStore.standard().save(newSettings)
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
        }
    }

    private func ageText(_ days: Int) -> String {
        days == 365 ? tr("1 year") : tr("%1$@ days", "\(days)")
    }

    /// Whether a check runs, as a switch. Turning it off adds it to the list of checks
    /// that are turned off.
    private func runs(_ id: String) -> Binding<Bool> {
        Binding(
            get: { !settings.checksTurnedOff.contains(id) },
            set: { isOn in
                var turnedOff = Set(settings.checksTurnedOff)
                if isOn {
                    turnedOff.remove(id)
                } else {
                    turnedOff.insert(id)
                }
                settings.checksTurnedOff = turnedOff.sorted()
            }
        )
    }

    /// Lets the user pick folders to leave out. Nothing happens to the folders.
    private func addFolders() {
        let panel = NSOpenPanel()
        panel.title = tr("Choose folders to leave out")
        panel.prompt = tr("Leave Out")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else {
            return
        }
        for url in panel.urls {
            let path = url.standardizedFileURL.path
            if !settings.foldersLeftOut.contains(path) {
                settings.foldersLeftOut.append(path)
            }
        }
    }
}

/// One folder that is left out: a folder mark, the path, and a way to include it again.
private struct FolderRow: View {
    let path: String
    let includeAgain: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder")
                .font(.system(size: 15))
                .foregroundStyle(Color.siivosTint)
                .frame(width: 20, height: 20)
            Text(shortened)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
            Spacer(minLength: 12)
            Button(tr("Include Again")) {
                includeAgain()
            }
            .buttonStyle(SiivOSButtonStyle(.small))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// The path with the home folder written as "~", which is shorter to read.
    private var shortened: String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        return path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
    }
}

// MARK: - Holding area

/// When the holding area is emptied by itself, and when it is pointed out. Emptying is
/// off until a time is chosen here; what it does is said plainly next to the choice.
private struct HoldingAreaSettingsGroup: View {
    @State private var deleteAfterDays = HoldingAreaSettingsStore.standard().load().deleteAfterDays
    @State private var warnAboveBytes = HoldingAreaSettingsStore.standard().load().warnAboveBytes
    /// What has already waited as long as the chosen time, so the user sees what the
    /// choice will delete before it happens.
    @State private var alreadyWaiting: SafetyCore.WaitingItems?
    /// Why the settings could not be saved, if they could not.
    @State private var problem: String?

    var body: some View {
        SettingsGroup(tr("Holding area")) {
            SettingsPanel {
                SettingRow(tr("Delete items for good after they have waited"), notes: deleteNotes) {
                    SiivOSMenuPicker(
                        title: tr("Delete items for good after they have waited"),
                        selection: $deleteAfterDays,
                        options: HoldingAreaSettings.deleteAfterChoices.map { ($0, timeText($0)) }
                    )
                }
                ThemedDivider()
                SettingRow(
                    tr("Point out the holding area when it holds more than"),
                    notes: [tr("A line on the Overview and in History says so. Nothing is deleted because of this.")]
                ) {
                    SiivOSMenuPicker(
                        title: tr("Point out the holding area when it holds more than"),
                        selection: $warnAboveBytes,
                        options: HoldingAreaSettings.warnAboveChoices.map { ($0, $0 == 0 ? tr("Never") : formatBytes($0)) }
                    )
                }
                if let problem {
                    ThemedDivider()
                    SettingErrorLine(reason: problem)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
        .onAppear {
            lookAtWhatIsWaiting()
        }
        .onChange(of: deleteAfterDays) { _, _ in
            save()
            lookAtWhatIsWaiting()
        }
        .onChange(of: warnAboveBytes) { _, _ in
            save()
        }
    }

    private func timeText(_ days: Int) -> String {
        switch days {
        case 0: return tr("Never")
        case 365: return tr("1 year")
        default: return tr("%1$@ days", "\(days)")
        }
    }

    /// What the choice does, and what it is about to delete if anything.
    private var deleteNotes: [String] {
        var notes = [tr("Removed items wait in the holding area and still take up space there. With a time chosen, SiivOS deletes for good what has waited longer, which frees the space. Deleted items cannot be put back. SiivOS checks when it opens, and every half hour while it runs.")]
        if deleteAfterDays > 0, let waiting = alreadyWaiting, waiting.itemCount > 0 {
            let size = formatBytes(waiting.bytes)
            notes.append(
                waiting.itemCount == 1
                    ? tr("1 item (%1$@) has already waited that long. It will be deleted for good the next time SiivOS checks.", size)
                    : tr("%1$@ items (%2$@) have already waited that long. They will be deleted for good the next time SiivOS checks.", "\(waiting.itemCount)", size)
            )
        }
        return notes
    }

    /// Counts what has already waited as long as the chosen time. Only reads.
    private func lookAtWhatIsWaiting() {
        guard deleteAfterDays > 0, case .success(let core) = AppCore.shared else {
            alreadyWaiting = nil
            return
        }
        let cutoff = Date().addingTimeInterval(-Double(deleteAfterDays) * 86_400)
        alreadyWaiting = try? core.heldItems(removedBefore: cutoff)
    }

    /// Saves the two choices without touching anything else kept in the same file.
    private func save() {
        let store = HoldingAreaSettingsStore.standard()
        var current = store.load()
        current.deleteAfterDays = deleteAfterDays
        current.warnAboveBytes = warnAboveBytes
        do {
            try store.save(current)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        HoldingStatus.shared.refresh()
    }
}

// MARK: - Permissions

private struct PermissionsSettingsGroup: View {
    /// Whether macOS lets SiivOS see every folder. Looked up when the screen is shown and
    /// when SiivOS comes forward again, for example after a visit to System Settings.
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        SettingsGroup(tr("Permissions")) {
            SettingsPanel {
                SettingRow(tr("Full Disk Access")) {
                    SettingStatus(isOn: hasFullDiskAccess)
                }
                // Under the row at full width: the off note is long, and longer in Finnish.
                VStack(alignment: .leading, spacing: 12) {
                    SettingNoteText(
                        hasFullDiskAccess
                            ? tr("macOS lets SiivOS see every folder, so it does not ask folder by folder.")
                            : tr("Without it, macOS asks about one folder at a time, and some lists in SiivOS stay empty. Full Disk Access covers everything in one go. macOS only lets you turn it on yourself: open the page below and switch SiivOS on in the list. If SiivOS is not in the list, add it with the + button. macOS may then ask you to quit and reopen SiivOS.")
                    )
                    // The main action while access is off; an ordinary button once it is on.
                    if hasFullDiskAccess {
                        Button(tr("Open Full Disk Access Settings")) {
                            openFullDiskAccessSettings()
                        }
                        .buttonStyle(SiivOSButtonStyle(.standard))
                    } else {
                        ProminentButton(tr("Open Full Disk Access Settings")) {
                            openFullDiskAccessSettings()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

                ThemedDivider()
                // No On or Off here: macOS gives an app no way to find out whether it
                // has this permission, and SiivOS does not guess.
                SettingRow(
                    tr("App Management"),
                    notes: [tr("Lets SiivOS move an app out of the Applications folder when you uninstall it. macOS gives apps no way to see whether they have this permission, so SiivOS cannot show it here. If macOS stops an uninstall, open Privacy & Security, then App Management, and switch SiivOS on.")]
                ) {
                    Button(tr("Open App Management Settings")) {
                        openAppManagementSettings()
                    }
                    .buttonStyle(SiivOSButtonStyle(.small))
                }
            }
        }
        .onAppear {
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
    }

    /// Opens the App Management page, as confirmed on macOS 15.8.3. Should a macOS not
    /// know the page by this name, it opens Privacy & Security, and the row's note says
    /// where to go from there.
    private func openAppManagementSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AppBundles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - AI agents

private struct AgentSettingsGroup: View {
    /// Whether the agent door is on. Kept in a file, not in the app's own settings,
    /// because the command-line tool is a separate program that has to read it too.
    @State private var agentDoorIsOn = AgentDoorSwitch.standard().isOn
    /// Why the agent door could not be switched, if it could not.
    @State private var problem: String?

    var body: some View {
        SettingsGroup(tr("AI agents")) {
            SettingsPanel {
                SettingRow(
                    tr("Let AI agents ask SiivOS questions"),
                    notes: [
                        tr("With this on, the command-line tool that comes with SiivOS answers questions from an AI agent you use, such as what is taking space or what has changed lately. The tool only reads. It cannot remove or change anything."),
                        tr("SiivOS itself sends nothing anywhere. An agent that runs on the internet, though, sends what it reads to its own service, including the names of your files and apps.")
                    ]
                ) {
                    SettingSwitch(title: tr("Let AI agents ask SiivOS questions"), isOn: agentDoor)
                }
                if let problem {
                    SettingErrorLine(reason: problem)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)
                }
                ThemedDivider()
                VStack(alignment: .leading, spacing: 8) {
                    if let path = toolPath {
                        SettingPathField(path: path)
                        SettingNoteText(tr("This is where the tool is. Give the path to your agent, or try it in Terminal by typing the word help after it."))
                        SettingNoteText(tr("If your agent uses MCP servers, add SiivOS with this path as the command and the word mcp as its one argument."))
                    } else {
                        SettingNoteText(tr("The tool is put inside the app when SiivOS is built with Scripts/make-app.sh. This copy of SiivOS was started another way, so the tool is not in it."))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    /// Switches the agent door, and keeps the switch where it was if that fails.
    private var agentDoor: Binding<Bool> {
        Binding(
            get: { agentDoorIsOn },
            set: { isOn in
                do {
                    try AgentDoorSwitch.standard().set(isOn)
                    agentDoorIsOn = isOn
                    problem = nil
                } catch {
                    problem = error.localizedDescription
                }
            }
        )
    }

    /// Where the command-line tool is: inside the app, or next to it when SiivOS was
    /// built without an app around it. `nil` when it is in neither place.
    private var toolPath: String? {
        let name = AgentDoor.toolName
        let places: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/" + name),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent(name)
        ]
        return places
            .compactMap { $0 }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }?
            .path
    }
}

// MARK: - Privacy

/// Not a setting, but Settings is where people look for what an app does with their
/// data, and placed after AI agents it answers the question the agent notes raise.
private struct PrivacyGroup: View {
    var body: some View {
        SettingsGroup(tr("Privacy")) {
            SettingsPanel {
                HStack(alignment: .top, spacing: 12) {
                    SiivOSIconView(.protection, size: 26)
                    Text(tr("Everything SiivOS does happens on this Mac. It collects nothing and sends nothing anywhere. The one time it uses the network is when you ask it, in Protection, to download ClamAV's virus definitions."))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
            }
        }
    }
}
