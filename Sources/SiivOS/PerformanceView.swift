import AppKit
import SiivOSCore
import SwiftUI

/// A live look at the processor, memory, disk and battery, with what SiivOS makes of it.
/// Nothing on this screen changes anything.
struct PerformanceView: View {
    @ObservedObject var model: PerformanceModel
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
                    gauges(sample)
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
                DiagnosisCard(diagnosis: diagnosis, open: open)
            }
        }
    }

    // MARK: - Gauges

    private func gauges(_ sample: PerformanceSample) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Right now"))
                .font(.title3)
                .bold()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320), spacing: 16, alignment: .top)],
                alignment: .leading,
                spacing: 16
            ) {
                ProcessorCard(sample: sample, history: model.samples.map { $0.cpuUsedFraction ?? 0 })
                if let memory = sample.memory {
                    MemoryCard(
                        sample: sample,
                        memory: memory,
                        history: model.samples.map { $0.memory?.usedFraction ?? 0 }
                    )
                }
                DiskCard(sample: sample)
                if let battery = sample.battery {
                    BatteryCard(battery: battery)
                }
            }
        }
    }
}

/// One thing SiivOS noticed, in calm wording, with a way to act on it where there is one.
private struct DiagnosisCard: View {
    let diagnosis: Diagnosis
    let open: (AppSection) -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Color.siivosTint)
                    .frame(width: 28)
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

    private var symbol: String {
        switch diagnosis.level {
        case .good: return "checkmark.circle"
        case .note: return "info.circle"
        case .attention: return "exclamationmark.circle"
        }
    }
}

// MARK: - Cards

private struct ProcessorCard: View {
    let sample: PerformanceSample
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                GaugeTitle(text: tr("Processor"), symbol: "cpu")
                Text(headline)
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text(tr("in use, across %1$@ cores", "\(sample.coreCount)"))
                    .foregroundStyle(.secondary)
                Sparkline(values: history)

                if !sample.topByCPU.isEmpty {
                    Divider()
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

private struct MemoryCard: View {
    let sample: PerformanceSample
    let memory: MemoryUsage
    let history: [Double]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                GaugeTitle(text: tr("Memory"), symbol: "memorychip")
                Text(formatMemory(memory.usedBytes))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text(tr("in use, of %1$@", formatMemory(memory.totalBytes)))
                    .foregroundStyle(.secondary)
                Sparkline(values: history)
                Text(pressureText)
                    .fixedSize(horizontal: false, vertical: true)
                if memory.swapUsedBytes > 0 {
                    Text(tr("%1$@ has been moved to the disk to make room.", formatMemory(memory.swapUsedBytes)))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !sample.topByMemory.isEmpty {
                    Divider()
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

private struct DiskCard: View {
    let sample: PerformanceSample

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                GaugeTitle(text: tr("Startup disk"), symbol: "internaldrive")
                if let total = sample.diskTotalBytes, let available = sample.diskAvailableBytes {
                    Text(formatBytes(available))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                    Text(tr("free, of %1$@", formatBytes(total)))
                        .foregroundStyle(.secondary)
                    ProgressView(value: 1 - (sample.diskFreeFraction ?? 0))
                        .tint(Color.siivosMoss)
                } else {
                    Text(tr("The disk could not be read."))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BatteryCard: View {
    let battery: BatteryStatus

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                GaugeTitle(text: tr("Battery"), symbol: "battery.75percent")
                Text(formatPercent(Double(battery.chargePercent) / 100))
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                Text(stateText)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let health = battery.healthPercent {
                    Divider()
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

/// The heading of a gauge card: a tinted symbol and a name.
private struct GaugeTitle: View {
    let text: String
    let symbol: String

    var body: some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.siivosTint)
        }
        .font(.headline)
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

/// A small line chart of recent readings, newest at the right edge.
private struct Sparkline: View {
    /// Readings from 0 to 1, oldest first.
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                guard values.count > 1 else {
                    return
                }
                let slot = proxy.size.width / CGFloat(PerformanceModel.historyLimit - 1)
                for (index, value) in values.enumerated() {
                    let fromRight = CGFloat(values.count - 1 - index)
                    let level = CGFloat(min(1, max(0, value)))
                    let point = CGPoint(
                        x: proxy.size.width - fromRight * slot,
                        y: proxy.size.height * (1 - level)
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(Color.siivosTint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Divider()
        }
        .accessibilityHidden(true)
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
