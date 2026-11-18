import AppKit
import SiivOSCore
import SwiftUI

/// The Settings window, opened from the SiivOS menu or with Command-comma. One tab for
/// each kind of setting, as Mac apps usually have them.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsPane()
                .tabItem {
                    Label(tr("General"), systemImage: "gearshape")
                }
            CleanupSettingsPane()
                .tabItem {
                    Label(tr("Cleanup"), systemImage: "sparkles")
                }
            PermissionsSettingsPane()
                .tabItem {
                    Label(tr("Permissions"), systemImage: "lock")
                }
            AgentSettingsPane()
                .tabItem {
                    Label(tr("AI agents"), systemImage: "terminal")
                }
        }
        .tint(SiivOSTheme.prominent)
        .frame(width: 560, height: 500)
    }
}

/// Small explanatory text under a setting.
private struct SettingNote: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @AppStorage(AppSettings.showsMenuBarKey) private var showsMenuBar = true

    var body: some View {
        Form {
            Section {
                Toggle(tr("Show SiivOS in the menu bar"), isOn: $showsMenuBar)
                SettingNote(tr("With this on, SiivOS stays in the menu bar after you close its window, shows the health score there and takes a reading every six hours. To stop it, choose Quit SiivOS in the menu bar or press Command-Q."))
            }
            Section(tr("Privacy")) {
                Text(tr("Everything SiivOS does happens on this Mac. It collects nothing and sends nothing anywhere. The one time it uses the network is when you ask it, in Protection, to download ClamAV's virus definitions."))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
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
private struct CleanupSettingsPane: View {
    @State private var settings = CleanupSettingsStore.standard().load()
    /// Why the settings could not be saved, if they could not.
    @State private var problem: String?

    private let checks = ScanEngine.clutterChecks.map { CheckChoice(id: $0.id, title: $0.title) }

    var body: some View {
        Form {
            Section {
                Picker(tr("A download counts as old after"), selection: $settings.oldDownloadDays) {
                    ForEach(CleanupSettings.oldDownloadChoices, id: \.self) { days in
                        Text(ageText(days)).tag(days)
                    }
                }
                Picker(tr("A file counts as large from"), selection: $settings.largeFileBytes) {
                    ForEach(CleanupSettings.largeFileChoices, id: \.self) { bytes in
                        Text(formatBytes(bytes)).tag(bytes)
                    }
                }
            }

            Section(tr("Checks to run")) {
                ForEach(checks) { check in
                    Toggle(check.title, isOn: runs(check.id))
                }
            }

            Section(tr("Folders to leave out")) {
                SettingNote(tr("Nothing in these folders is listed in Cleanup, whichever check would have found it. The folders themselves are not touched."))
                ForEach(settings.foldersLeftOut, id: \.self) { path in
                    HStack(spacing: 10) {
                        Text(shortened(path))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(path)
                        Spacer()
                        Button(tr("Include Again")) {
                            settings.foldersLeftOut.removeAll { $0 == path }
                        }
                        .buttonStyle(SiivOSButtonStyle(.small))
                    }
                }
                Button(tr("Add Folder…")) {
                    addFolders()
                }
                .buttonStyle(SiivOSButtonStyle(.small))
            }

            Section {
                SettingNote(tr("Changes apply the next time you scan."))
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings) { _, newSettings in
            do {
                try CleanupSettingsStore.standard().save(newSettings)
                problem = nil
            } catch {
                problem = tr("The setting could not be saved: %1$@", error.localizedDescription)
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

    /// The path with the home folder written as "~", which is shorter to read.
    private func shortened(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home {
            return "~"
        }
        return path.hasPrefix(home + "/") ? "~" + String(path.dropFirst(home.count)) : path
    }
}

// MARK: - Permissions

private struct PermissionsSettingsPane: View {
    /// Whether macOS lets SiivOS see every folder. Looked up when the tab is shown and
    /// when SiivOS comes forward again, for example after a visit to System Settings.
    @State private var hasFullDiskAccess = Permissions.hasFullDiskAccess()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text(tr("Full Disk Access"))
                    Spacer()
                    Text(hasFullDiskAccess ? tr("On") : tr("Off"))
                        .foregroundStyle(.secondary)
                }
                SettingNote(
                    hasFullDiskAccess
                        ? tr("macOS lets SiivOS see every folder, so it does not ask folder by folder.")
                        : tr("Without it, macOS asks about one folder at a time, and some lists in SiivOS stay empty. Full Disk Access covers everything in one go. macOS only lets you turn it on yourself: open the page below and switch SiivOS on in the list. If SiivOS is not in the list, add it with the + button. macOS may then ask you to quit and reopen SiivOS.")
                )
                Button(tr("Open Full Disk Access Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(SiivOSButtonStyle(.small))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasFullDiskAccess = Permissions.hasFullDiskAccess()
        }
    }
}

// MARK: - AI agents

private struct AgentSettingsPane: View {
    /// Whether the agent door is on. Kept in a file, not in the app's own settings,
    /// because the command-line tool is a separate program that has to read it too.
    @State private var agentDoorIsOn = AgentDoorSwitch.standard().isOn
    /// Why the agent door could not be switched, if it could not.
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Toggle(tr("Let AI agents ask SiivOS questions"), isOn: agentDoor)
                SettingNote(tr("With this on, the command-line tool that comes with SiivOS answers questions from an AI agent you use, such as what is taking space or what has changed lately. The tool only reads. It cannot remove or change anything."))
                SettingNote(tr("SiivOS itself sends nothing anywhere. An agent that runs on the internet, though, sends what it reads to its own service, including the names of your files and apps."))
                if let problem {
                    Text(problem)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section {
                if let path = toolPath {
                    HStack(spacing: 10) {
                        Text(path)
                            .font(.system(.callout, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(path)
                        Spacer()
                        Button(tr("Copy Path")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(path, forType: .string)
                        }
                        .buttonStyle(SiivOSButtonStyle(.small))
                    }
                    SettingNote(tr("This is where the tool is. Give the path to your agent, or try it in Terminal by typing the word help after it."))
                    SettingNote(tr("If your agent uses MCP servers, add SiivOS with this path as the command and the word mcp as its one argument."))
                } else {
                    SettingNote(tr("The tool is put inside the app when SiivOS is built with Scripts/make-app.sh. This copy of SiivOS was started another way, so the tool is not in it."))
                }
            }
        }
        .formStyle(.grouped)
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
                    problem = tr("The setting could not be saved: %1$@", error.localizedDescription)
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
