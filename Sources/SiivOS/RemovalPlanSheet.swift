import SiivOSCore
import SwiftUI

/// The explanation shown before anything is removed. Nothing changes until the user confirms.
struct RemovalPlanSheet: View {
    let plan: RemovalPlan
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(plan.items.isEmpty ? tr("Nothing can be removed") : tr("Before anything changes"))
                .font(.title2)
                .bold()
            Text(plan.explanation)
                .fixedSize(horizontal: false, vertical: true)

            if !plan.items.isEmpty {
                GroupBox(tr("Will be moved to the holding area")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(plan.items) { item in
                                HStack {
                                    Text(item.url.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(formatBytes(item.sizeBytes))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .frame(maxHeight: 160)
                }
            }

            if !plan.refused.isEmpty {
                GroupBox(tr("Will be left alone")) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(plan.refused) { refusal in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(refusal.url.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(refusal.reason)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .frame(maxHeight: 120)
                }
            }

            HStack {
                Spacer()
                Button(plan.items.isEmpty ? tr("Close") : tr("Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if !plan.items.isEmpty {
                    Button(tr("Move to Holding Area"), action: onConfirm)
                }
            }
        }
        .padding(20)
        .frame(width: 540)
    }
}
