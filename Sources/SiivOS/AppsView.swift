import AppKit
import SiivOSCore
import SwiftUI

/// Lists installed apps and background items, and lets the user remove them.
struct AppsView: View {
    @ObservedObject var model: AppsModel
    @State private var tab: Tab = .apps

    private enum Tab: Hashable {
        case apps
        case background
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker(tr("View"), selection: $tab) {
                Text(tr("Apps")).tag(Tab.apps)
                Text(tr("Background Items")).tag(Tab.background)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            content
        }
        .navigationTitle(tr("Apps"))
        .onAppear {
            if !model.hasLoaded {
                model.load()
            }
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
        if model.isLoading {
            LoadingView(text: progressText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if tab == .apps {
            AppListView(model: model)
        } else {
            BackgroundItemsView(model: model)
        }
    }

    private var progressText: String {
        model.loadingName.isEmpty ? tr("Looking for apps…") : tr("Measuring %1$@…", model.loadingName)
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

// MARK: - Apps

private struct AppListView: View {
    @ObservedObject var model: AppsModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField(tr("Search apps"), text: $model.searchText)
                    .textFieldStyle(.roundedBorder)
                Picker(tr("Sort by"), selection: $model.sortOrder) {
                    ForEach(AppsModel.SortOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                .frame(width: 260)
                Button(tr("Refresh")) {
                    model.load()
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)

            List(model.visibleApps) { info in
                AppRow(
                    info: info,
                    isWorking: model.isWorking,
                    onUninstall: { model.prepareUninstall(info) }
                )
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct AppRow: View {
    let info: AppInfo
    let isWorking: Bool
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: info.app.url.path))
                .resizable()
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.app.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatBytes(info.sizeBytes))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if info.isPartOfMacOS {
                Text(tr("Part of macOS"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 110)
            } else {
                Button(tr("Uninstall…"), action: onUninstall)
                    .disabled(isWorking)
                    .frame(width: 110)
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(tr("Show in Finder")) {
                NSWorkspace.shared.activateFileViewerSelecting([info.app.url])
            }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let version = info.app.version {
            parts.append(tr("Version %1$@", version))
        }
        if let lastUsed = info.lastUsed {
            parts.append(tr("Last opened %1$@", lastUsed.formatted(date: .abbreviated, time: .omitted)))
        } else {
            parts.append(tr("No record of it being opened"))
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Background items

private struct BackgroundItemsView: View {
    @ObservedObject var model: AppsModel

    var body: some View {
        Form {
            Section {
                Text(tr("Background items are programs macOS starts by itself, without you opening them. Each one is set up by a small settings file; removing that file stops the program from starting."))
                Text(tr("Apps that open when you log in are managed by macOS itself. SiivOS cannot list those, but you can review them in System Settings."))
                Button(tr("Open Login Items Settings")) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }

            BackgroundSection(
                model: model,
                title: tr("For your account"),
                note: tr("These start when you log in. SiivOS can remove them."),
                items: model.backgroundItems(in: .user),
                canRemove: true
            )
            BackgroundSection(
                model: model,
                title: tr("For all users of this Mac"),
                note: tr("These start when anyone logs in. Removing them needs an administrator, so SiivOS only shows them."),
                items: model.backgroundItems(in: .allUsers),
                canRemove: false
            )
            BackgroundSection(
                model: model,
                title: tr("For the Mac itself"),
                note: tr("These start with the Mac, before anyone logs in. Removing them needs an administrator, so SiivOS only shows them."),
                items: model.backgroundItems(in: .system),
                canRemove: false
            )
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct BackgroundSection: View {
    @ObservedObject var model: AppsModel
    let title: String
    let note: String
    let items: [BackgroundItem]
    let canRemove: Bool

    var body: some View {
        Section(title) {
            Text(note)
                .font(.callout)
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text(tr("None."))
                    .foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                BackgroundRow(
                    item: item,
                    canRemove: canRemove,
                    isWorking: model.isWorking,
                    onRemove: { model.prepareRemoval(of: item) }
                )
            }
        }
    }
}

private struct BackgroundRow: View {
    let item: BackgroundItem
    let canRemove: Bool
    let isWorking: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.label)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let program = item.program {
                    Text(program)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if !item.programExists {
                    Label(tr("Its program is missing. It was probably left behind by an app you removed."), systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canRemove {
                Button(tr("Remove…"), action: onRemove)
                    .disabled(isWorking)
            } else {
                Button(tr("Show in Finder")) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.url])
                }
            }
        }
        .buttonStyle(.bordered)
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if item.isDisabled {
            return tr("Turned off")
        }
        if item.startsAutomatically {
            return item.scope == .system ? tr("Starts with the Mac") : tr("Starts at login")
        }
        return tr("Starts only when something needs it")
    }
}
