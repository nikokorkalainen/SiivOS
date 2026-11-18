import AppKit
import SiivOSCore
import SwiftUI

/// A live look at the processor, memory, disk and battery, with what SiivOS makes of it.
/// Nothing on this screen changes anything. Its look follows the Performance section of
/// docs/design.md.
struct PerformanceView: View {
    @ObservedObject var model: PerformanceModel
    /// The last Cleanup check, so the disk panel can say what is safe to remove.
    @ObservedObject var cleanup: CleanupModel
    /// Opens another section of the app.
    let open: (AppSection) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageHeader(
                    title: tr("Performance"),
                    subtitle: tr("A live look at what this Mac is doing. Looking changes nothing.")
                ) {
                    Button(tr("Open Activity Monitor")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                    }
                    .help(tr("Activity Monitor is the macOS app for seeing and quitting programs."))
                }

                if let sample = model.latest {
                    noticed
                    panels(sample)
                } else {
                    LoadingView(text: tr("Taking the first readings…"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                }
            }
            .padding(24)
            .readableWidth()
        }
        .navigationTitle(tr("Performance"))
        .task {
            await model.run()
        }
    }

    // MARK: - What SiivOS notices

    private var noticed: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("What SiivOS notices"))
                .font(.title3)
                .bold()
            ForEach(model.diagnoses) { diagnosis in
                DiagnosisPanel(diagnosis: diagnosis, open: open)
            }
        }
    }

    // MARK: - Right now

    /// Four panels, two across on a normal window and one on a narrow one.
    private func panels(_ sample: PerformanceSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Right now"))
                .font(.title3)
                .bold()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ProcessorPanel(sample: sample, history: model.samples.map { $0.cpuUsedFraction ?? 0 })
                if let memory = sample.memory {
                    MemoryPanel(
                        sample: sample,
                        memory: memory,
                        history: model.samples.map { $0.memory?.usedFraction ?? 0 }
                    )
                }
                DiskPanel(sample: sample, safeToRemoveBytes: cleanup.safeToRemoveBytes, open: open)
                if let battery = sample.battery {
                    BatteryPanel(battery: battery)
                }
            }
        }
    }
}

/// One thing SiivOS noticed: a round icon, the title, and the explanation in calm wording.
/// The all-clear message uses the same panel.
private struct DiagnosisPanel: View {
    let diagnosis: Diagnosis
    let open: (AppSection) -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .resizable()
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.siivosTint)
                    .frame(width: 34, height: 34)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(diagnosis.title)
                        .font(.headline)
                    Text(diagnosis.explanation)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if diagnosis.suggestion == .openCleanup {
                        Button(tr("Open Cleanup")) {
                            open(.cleanup)
                        }
                        .padding(.top, 4)
                    } else if diagnosis.suggestion == .openApps {
                        Button(tr("Open Apps")) {
                            open(.apps)
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    /// A check for good news, an "i" for a note, an exclamation mark when something is
    /// slowing the Mac down. All in the same calm tint.
    private var symbol: String {
        switch diagnosis.level {
        case .good: return "checkmark.circle.fill"
        case .note: return "info.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Panels

private struct ProcessorPanel: View {
    let sample: PerformanceSample
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeading(
                    title: tr("Processor"),
                    number: headline,
                    context: tr("in use, across %1$@ cores", "\(sample.coreCount)")
                )
                Sparkline(values: history)

                if !sample.topByCPU.isEmpty {
                    ThemedDivider()
                    Text(tr("Busiest now"))
                        .font(.subheadline)
                        .bold()
                    ForEach(sample.topByCPU) { usage in
                        ProcessRow(usage: usage, value: share(of: usage))
                    }
                }
            }
        }
    }

    private var headline: String {
        guard let fraction = sample.cpuUsedFraction else {
            return "…"
        }
        return formatPercent(fraction)
    }

    /// A program's share of the whole processor, so the numbers add up to the big one above.
    private func share(of usage: ProcessUsage) -> String {
        formatPercent(usage.cpuPercent / 100 / Double(max(1, sample.coreCount)))
    }
}

private struct MemoryPanel: View {
    let sample: PerformanceSample
    let memory: MemoryUsage
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeading(
                    title: tr("Memory"),
                    number: formatMemory(memory.usedBytes),
                    context: tr("in use, of %1$@", formatMemory(memory.totalBytes))
                )
                Sparkline(values: history)

                PressureMeter(pressure: memory.pressure)
                Text(pressureText)
                    .fixedSize(horizontal: false, vertical: true)
                if memory.swapUsedBytes > 0 {
                    Text(tr("%1$@ has been moved to the disk to make room.", formatMemory(memory.swapUsedBytes)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !sample.topByMemory.isEmpty {
                    ThemedDivider()
                    Text(tr("Using the most"))
                        .font(.subheadline)
                        .bold()
                    ForEach(sample.topByMemory) { usage in
                        ProcessRow(usage: usage, value: formatMemory(usage.memoryBytes))
                    }
                }
            }
        }
    }

    private var pressureText: String {
        switch memory.pressure {
        case .normal:
            return tr("There is room to spare. macOS fills unused memory on purpose, so a high number here is normal.")
        case .elevated:
            return tr("Memory is getting tight. macOS is squeezing it to make room.")
        case .high:
            return tr("Memory is under heavy pressure. Apps are waiting for memory.")
        }
    }
}

private struct DiskPanel: View {
    let sample: PerformanceSample
    /// What the last Cleanup check found safe to remove, or zero when there is nothing to say.
    let safeToRemoveBytes: Int64
    let open: (AppSection) -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                if let total = sample.diskTotalBytes, let available = sample.diskAvailableBytes {
                    PanelHeading(
                        title: tr("Startup disk"),
                        number: formatBytes(available),
                        context: tr("free, of %1$@", formatBytes(total))
                    )
                    MeterBar(fraction: 1 - (sample.diskFreeFraction ?? 0))

                    if safeToRemoveBytes > 0 {
                        ThemedDivider()
                        Text(tr("Cleanup found %1$@ that is safe to remove.", formatBytes(safeToRemoveBytes)))
                            .fixedSize(horizontal: false, vertical: true)
                        Button(tr("Open Cleanup")) {
                            open(.cleanup)
                        }
                    }
                } else {
                    Text(tr("Startup disk"))
                        .font(.headline)
                    Text(tr("The disk could not be read."))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BatteryPanel: View {
    let battery: BatteryStatus

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                PanelHeading(
                    title: tr("Battery"),
                    number: formatPercent(Double(battery.chargePercent) / 100),
                    context: stateText
                )
                MeterBar(fraction: Double(battery.chargePercent) / 100)

                if battery.healthPercent != nil || battery.cycleCount != nil {
                    ThemedDivider()
                }
                if let health = battery.healthPercent {
                    Text(tr("Holds about %1$@ of what it did when new.", formatPercent(Double(health) / 100)))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let cycles = battery.cycleCount {
                    Text(tr("%1$@ charge cycles so far.", "\(cycles)"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var stateText: String {
        if battery.isCharging {
            if let minutes = battery.minutesRemaining {
                return tr("Charging. About %1$@ until full.", formatDuration(minutes: minutes))
            }
            return tr("Charging.")
        }
        if battery.isPluggedIn {
            return tr("Plugged in, not charging.")
        }
        if let minutes = battery.minutesRemaining {
            return tr("On battery. About %1$@ left.", formatDuration(minutes: minutes))
        }
        return tr("On battery.")
    }
}

// MARK: - Building blocks

/// The top of a panel: a plain title, a large number, and one line of context.
/// No icon; the sidebar already says where you are.
private struct PanelHeading: View {
    let title: String
    let number: String
    let context: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(number)
                .font(.system(size: 32, weight: .semibold))
                .monospacedDigit()
            Text(context)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Memory pressure in three steps: normal, tight, heavy. One step is lit when there is
/// room to spare, all three when apps are waiting for memory.
private struct PressureMeter: View {
    let pressure: MemoryUsage.Pressure

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { step in
                Capsule()
                    .fill(step <= pressure.rawValue ? Color.siivosTint : SiivOSTheme.divider)
                    .frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// One program in a "biggest users" list, with what it is where SiivOS knows.
private struct ProcessRow: View {
    let usage: ProcessUsage
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let explanation = KnownProcesses.explanation(for: usage.name) {
                    Text(explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var name: String {
        usage.count > 1 ? "\(usage.name) × \(usage.count)" : usage.name
    }
}

/// A small chart of recent readings, newest at the right edge: a 2 pt line in the tint
/// colour over a soft fade of the same colour, with no axes.
private struct Sparkline: View {
    /// Readings from 0 to 1, oldest first.
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = self.points(in: proxy.size)
            ZStack {
                area(through: points, height: proxy.size.height)
                    .fill(
                        LinearGradient(
                            colors: [Color.siivosTint.opacity(0.3), Color.siivosTint.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                line(through: points)
                    .stroke(Color.siivosTint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }

    /// Where each reading sits. Each has a fixed slot, so the line grows in from the right.
    private func points(in size: CGSize) -> [CGPoint] {
        let slot = size.width / CGFloat(PerformanceModel.historyLimit - 1)
        // Leave room for the line's own thickness at the top and bottom.
        let inset: CGFloat = 2
        let usableHeight = max(0, size.height - inset * 2)
        var result: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let fromRight = CGFloat(values.count - 1 - index)
            let level = CGFloat(min(1, max(0, value)))
            result.append(
                CGPoint(x: size.width - fromRight * slot, y: inset + usableHeight * (1 - level))
            )
        }
        return result
    }

    private func line(through points: [CGPoint]) -> Path {
        var path = Path()
        guard points.count > 1, let first = points.first else {
            return path
        }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// The shape under the line, down to the bottom edge.
    private func area(through points: [CGPoint], height: CGFloat) -> Path {
        var path = line(through: points)
        guard points.count > 1, let first = points.first, let last = points.last else {
            return path
        }
        path.addLine(to: CGPoint(x: last.x, y: height))
        path.addLine(to: CGPoint(x: first.x, y: height))
        path.closeSubpath()
        return path
    }
}

// MARK: - Wording

/// A share written out for people, for example "85 %".
private func formatPercent(_ fraction: Double) -> String {
    min(1, max(0, fraction)).formatted(.percent.precision(.fractionLength(0)))
}

/// An amount of memory written out for people, for example "8 GB".
private func formatMemory(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
}

/// A length of time written out for people, for example "4 hr, 12 min".
private func formatDuration(minutes: Int) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.hour, .minute]
    formatter.unitsStyle = .short
    return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
}
