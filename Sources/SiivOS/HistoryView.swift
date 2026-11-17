import SiivOSCore
import SwiftUI

/// Shows every change SiivOS has made and lets the user put things back.
struct HistoryView: View {
    @StateObject private var model = HistoryModel()
    @State private var recordToDelete: ActionRecord?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(title: tr("History"), subtitle: holdingAreaText) {
                    Button(tr("Remove a File or Folder…")) {
                        model.chooseItemsToRemove()
                    }
                    .disabled(model.isWorking)
                    .help(tr("Choose something to move to the holding area. You will see an explanation first."))
                }

                if model.records.isEmpty {
                    Text(tr("SiivOS has not changed anything yet."))
                        .foregroundStyle(.secondary)
                } else {
                    changesList
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(tr("History"))
        .sheet(item: $model.pendingPlan) { plan in
            RemovalPlanSheet(
                plan: plan,
                onConfirm: { model.confirmPendingPlan() },
                onCancel: { model.pendingPlan = nil }
            )
        }
        .confirmationDialog(
            tr("Delete permanently?"),
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: recordToDelete
        ) { record in
            Button(tr("Delete Permanently"), role: .destructive) {
                model.deletePermanently(record)
            }
            Button(tr("Cancel"), role: .cancel) {}
        } message: { record in
            Text(tr("This deletes the held items from “%1$@” for good and frees %2$@. It cannot be undone.", record.title, formatBytes(record.heldBytes)))
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

    /// One line on what is waiting in the holding area.
    private var holdingAreaText: String {
        guard model.heldBytes > 0 else {
            return tr("The holding area is empty.")
        }
        return tr(
            "%1$@ is waiting in the holding area. Put items back, or delete them permanently to free the space.",
            formatBytes(model.heldBytes)
        )
    }

    /// Every change in one grouped list, newest first.
    private var changesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.records.enumerated()), id: \.element.id) { index, record in
                if index > 0 {
                    Divider()
                }
                RecordRow(
                    record: record,
                    isWorking: model.isWorking,
                    onPutBack: { model.putBack(record) },
                    onDelete: { recordToDelete = record }
                )
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
    }

    /// True while the "delete permanently" question is on screen.
    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { recordToDelete != nil },
            set: { isShown in
                if !isShown { recordToDelete = nil }
            }
        )
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

/// One change in the history list.
private struct RecordRow: View {
    let record: ActionRecord
    let isWorking: Bool
    let onPutBack: () -> Void
    let onDelete: () -> Void

    @State private var showsDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Button {
                    showsDetails.toggle()
                } label: {
                    Image(systemName: showsDetails ? "chevron.down" : "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if record.canUndo {
                    Button(tr("Put Back"), action: onPutBack)
                        .disabled(isWorking)
                    Button(tr("Delete Permanently…"), role: .destructive, action: onDelete)
                        .buttonStyle(.borderless)
                        .disabled(isWorking)
                } else {
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }
            }

            if showsDetails {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.explanation)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(record.items) { item in
                        Text("\(item.held.originalPath) (\(stateText(item.state)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }

    /// The date, the size and how many items, and where they are now if that is mixed.
    private var subtitle: String {
        let count = record.items.count
        var parts = [
            record.date.formatted(date: .abbreviated, time: .shortened),
            formatBytes(record.totalBytes),
            count == 1 ? tr("1 item") : tr("%1$@ items", "\(count)")
        ]
        if record.canUndo && record.count(of: .held) < count {
            parts.append(statusText)
        }
        return parts.joined(separator: ", ")
    }

    /// Where the items of this change are now, in a few words.
    private var statusText: String {
        let total = record.items.count
        let held = record.count(of: .held)
        let restored = record.count(of: .restored)
        let deleted = record.count(of: .deleted)

        if held == total { return tr("In the holding area") }
        if restored == total { return tr("Put back") }
        if deleted == total { return tr("Deleted permanently") }

        var parts: [String] = []
        if held > 0 { parts.append(tr("%1$@ in the holding area", "\(held)")) }
        if restored > 0 { parts.append(tr("%1$@ put back", "\(restored)")) }
        if deleted > 0 { parts.append(tr("%1$@ deleted", "\(deleted)")) }
        return parts.joined(separator: ", ")
    }

    private func stateText(_ state: ActionRecord.ItemState) -> String {
        switch state {
        case .held: return tr("in the holding area")
        case .restored: return tr("put back")
        case .deleted: return tr("deleted permanently")
        }
    }
}
