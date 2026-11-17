import SiivOSCore
import SwiftUI

/// Read-only summary of this Mac. Nothing on this screen changes the system.
struct OverviewView: View {
    @State private var snapshot = SystemSnapshot.current()

    var body: some View {
        Form {
            Section(tr("Startup disk")) {
                if let fraction = snapshot.diskUsedFraction {
                    ProgressView(value: fraction) {
                        Text(tr("%1$@ used", percent(fraction)))
                    }
                }
                LabeledContent(tr("Size"), value: bytes(snapshot.diskTotalBytes))
                LabeledContent(tr("Used"), value: bytes(snapshot.diskUsedBytes))
                LabeledContent(tr("Available"), value: bytes(snapshot.diskAvailableBytes))
            }

            Section(tr("This Mac")) {
                LabeledContent("macOS", value: snapshot.osVersion)
                LabeledContent(tr("Processor cores"), value: "\(snapshot.processorCount)")
                LabeledContent(tr("Memory"), value: memory(snapshot.physicalMemoryBytes))
                LabeledContent(tr("Time since restart"), value: uptime(snapshot.uptimeSeconds))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(tr("Overview"))
        .toolbar {
            ToolbarItem {
                Button {
                    snapshot = SystemSnapshot.current()
                } label: {
                    Label(tr("Refresh"), systemImage: "arrow.clockwise")
                }
                .help(tr("Read the current state of this Mac again"))
            }
        }
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value else { return tr("Unknown") }
        return ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func memory(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .memory)
    }

    private func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func uptime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? tr("Unknown")
    }
}
