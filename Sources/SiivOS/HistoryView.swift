import SiivOSCore
import SwiftUI

/// Shows every change SiivOS has made and lets the user put things back.
struct HistoryView: View {
    @StateObject private var model = HistoryModel()
    @State private var recordToDelete: ActionRecord?

    var body: some View {
        Form {
            Section("Holding area") {
                Text("SiivOS never deletes anything straight away. Removed items are moved to a holding area, and you can put them back from here.")
                LabeledContent("Waiting in the holding area", value: formatBytes(model.heldBytes))
                Button("Remove a File or Folder…") {
                    model.chooseItemsToRemove()
                }
                .disabled(model.isWorking)
                .help("Choose something to move to the holding area. You will see an explanation first.")
            }

            Section("Changes") {
                if model.records.isEmpty {
                    Text("SiivOS has not changed anything yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.records) { record in
                    RecordRow(
                        record: record,
                        isWorking: model.isWorking,
                        onPutBack: { model.putBack(record) },
                        onDelete: { recordToDelete = record }
                    )
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("History")
        .sheet(item: $model.pendingPlan) { plan in
            RemovalPlanSheet(
                plan: plan,
                onConfirm: { model.confirmPendingPlan() },
                onCancel: { model.pendingPlan = nil }
            )
        }
        .confirmationDialog(
            "Delete permanently?",
            isPresented: isConfirmingDeletion,
            titleVisibility: .visible,
            presenting: recordToDelete
        ) { record in
            Button("Delete Permanently", role: .destructive) {
                model.deletePermanently(record)
            }
            Button("Cancel", role: .cancel) {}
        } message: { record in
            Text("This deletes the held items from “\(record.title)” for good and frees \(formatBytes(record.heldBytes)). It cannot be undone.")
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
        VStack(alignment: .leading, spacing: 6) {
            Text(record.title)
                .font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DisclosureGroup("Details", isExpanded: $showsDetails) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.explanation)
                    ForEach(record.items) { item in
                        Text("\(item.held.originalPath) (\(stateText(item.state)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }

            if record.canUndo {
                HStack {
                    Button("Put Back", action: onPutBack)
                    Button("Delete Permanently…", role: .destructive, action: onDelete)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let date = record.date.formatted(date: .abbreviated, time: .shortened)
        return "\(date) · \(formatBytes(record.totalBytes)) · \(statusText)"
    }

    /// Where the items of this change are now, in a few words.
    private var statusText: String {
        let total = record.items.count
        let held = record.count(of: .held)
        let restored = record.count(of: .restored)
        let deleted = record.count(of: .deleted)

        if held == total { return "In the holding area" }
        if restored == total { return "Put back" }
        if deleted == total { return "Deleted permanently" }

        var parts: [String] = []
        if held > 0 { parts.append("\(held) in the holding area") }
        if restored > 0 { parts.append("\(restored) put back") }
        if deleted > 0 { parts.append("\(deleted) deleted") }
        return parts.joined(separator: ", ")
    }

    private func stateText(_ state: ActionRecord.ItemState) -> String {
        switch state {
        case .held: return "in the holding area"
        case .restored: return "put back"
        case .deleted: return "deleted permanently"
        }
    }
}
