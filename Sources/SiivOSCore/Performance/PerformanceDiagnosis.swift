import Foundation

/// Something SiivOS noticed about how the Mac is doing, said in plain words.
public struct Diagnosis: Equatable, Identifiable, Sendable {
    public enum Level: Int, Sendable {
        /// Nothing to do. Everything has room to spare.
        case good
        /// Worth knowing, but not slowing the Mac down much.
        case note
        /// This is slowing the Mac down right now.
        case attention
    }

    /// Where in SiivOS the user can do something about it.
    public enum Suggestion: Sendable {
        case openCleanup
        case openApps
    }

    /// Stable name of the rule, for example "disk-nearly-full".
    public let id: String
    public let level: Level
    public let title: String
    public let explanation: String
    public let suggestion: Suggestion?
}

/// The built-in rules that turn readings into diagnoses. Read-only, and honest about
/// what matters: a full disk, real memory pressure, a busy processor, heat. Memory that
/// is merely "in use" is not a problem, because macOS fills spare memory on purpose.
public enum PerformanceDiagnosis {
    /// How many of the most recent readings a rule looks at, so that one brief spike
    /// does not raise a diagnosis.
    private static let recentCount = 5

    /// - Parameter samples: Readings in the order they were taken, oldest first.
    /// - Returns: What is worth telling the user, most important first. Never empty:
    ///   when nothing is wrong, a single reassuring entry is returned.
    public static func evaluate(_ samples: [PerformanceSample]) -> [Diagnosis] {
        guard let latest = samples.last else {
            return []
        }
        let recent = Array(samples.suffix(recentCount))

        var found: [Diagnosis] = []
        found.append(contentsOf: disk(latest))
        found.append(contentsOf: memory(latest, recent: recent))
        found.append(contentsOf: processor(recent))
        found.append(contentsOf: heatAndPower(latest))
        found.append(contentsOf: battery(latest))

        if found.isEmpty {
            return [
                Diagnosis(
                    id: "all-good",
                    level: .good,
                    title: tr("Nothing is slowing this Mac down right now"),
                    explanation: tr("The processor, memory and disk all have room to spare."),
                    suggestion: nil
                )
            ]
        }
        // Most important first; rules of the same importance keep the order above.
        return found.enumerated()
            .sorted { first, second in
                if first.element.level != second.element.level {
                    return first.element.level.rawValue > second.element.level.rawValue
                }
                return first.offset < second.offset
            }
            .map { $0.element }
    }

    // MARK: - Rules

    private static func disk(_ sample: PerformanceSample) -> [Diagnosis] {
        guard let freeFraction = sample.diskFreeFraction, let available = sample.diskAvailableBytes else {
            return []
        }
        let free = bytes(available)
        if freeFraction < 0.10 || available < 10_000_000_000 {
            return [
                Diagnosis(
                    id: "disk-nearly-full",
                    level: .attention,
                    title: tr("The startup disk is nearly full"),
                    explanation: tr("Only %1$@ is free. macOS needs free space to work in, so a nearly full disk slows everything down. Cleanup can show you what is safe to remove.", free),
                    suggestion: .openCleanup
                )
            ]
        }
        if freeFraction < 0.20 {
            return [
                Diagnosis(
                    id: "disk-getting-full",
                    level: .note,
                    title: tr("The startup disk is getting full"),
                    explanation: tr("%1$@ is free. That is enough for now, but the Mac starts to slow down when the disk is almost full.", free),
                    suggestion: .openCleanup
                )
            ]
        }
        return []
    }

    private static func memory(_ latest: PerformanceSample, recent: [PerformanceSample]) -> [Diagnosis] {
        // Look at the last three readings, and act only when most of them agree.
        let lastFew = recent.suffix(3).compactMap { $0.memory?.pressure }
        guard !lastFew.isEmpty else {
            return []
        }
        let needed = lastFew.count >= 2 ? 2 : 1
        let high = lastFew.filter { $0 == .high }.count >= needed
        let tight = lastFew.filter { $0 != .normal }.count >= needed
        guard tight else {
            return []
        }

        let biggest = latest.topByMemory.prefix(2).map { $0.name }
        let who = biggest.isEmpty ? "" : " " + tr("The biggest right now: %1$@.", biggest.joined(separator: ", "))

        var found: [Diagnosis] = []
        if high {
            found.append(
                Diagnosis(
                    id: "memory-pressure-high",
                    level: .attention,
                    title: tr("Memory is under heavy pressure"),
                    explanation: tr("Open apps need more memory than this Mac has, so macOS keeps moving data to the disk and back, which is slow. Quitting apps you are not using helps the most.") + who,
                    suggestion: nil
                )
            )
        } else {
            found.append(
                Diagnosis(
                    id: "memory-pressure-elevated",
                    level: .note,
                    title: tr("Memory is getting tight"),
                    explanation: tr("macOS is squeezing memory to make room. The Mac still works well, but opening more apps may slow it down.") + who,
                    suggestion: nil
                )
            )
        }

        let days = Int(latest.uptimeSeconds / 86_400)
        if days >= 14 {
            found.append(
                Diagnosis(
                    id: "restart-may-help",
                    level: .note,
                    title: tr("A restart may help"),
                    explanation: tr("This Mac has been running for %1$@ days and memory is tight. Restarting clears out what apps have left behind over that time.", "\(days)"),
                    suggestion: nil
                )
            )
        }
        return found
    }

    private static func processor(_ recent: [PerformanceSample]) -> [Diagnosis] {
        let readings = recent.compactMap { $0.cpuUsedFraction }
        // A couple of readings are needed before "busy" means more than a brief spike.
        guard readings.count >= 3, let latest = recent.last else {
            return []
        }
        let average = readings.reduce(0, +) / Double(readings.count)
        let busiest = latest.topByCPU.first

        if average >= 0.80 {
            var explanation = tr("It has been about %1$@ busy for the last few moments, so everything else has to wait its turn.", percent(average))
            if let busiest {
                explanation += " " + tr("%1$@ is using the most.", busiest.name)
            }
            return [
                Diagnosis(
                    id: "processor-busy",
                    level: .attention,
                    title: tr("The processor is very busy"),
                    explanation: explanation,
                    suggestion: nil
                )
            ]
        }

        // One program keeping a whole core busy in every recent reading.
        if let busiest {
            let shares = recent.map { sample in
                sample.topByCPU.first { $0.name == busiest.name }?.cpuPercent ?? 0
            }
            if shares.count >= 3, shares.allSatisfy({ $0 >= 90 }) {
                let typical = shares.reduce(0, +) / Double(shares.count)
                return [
                    Diagnosis(
                        id: "one-program-working-hard",
                        level: .note,
                        title: tr("%1$@ is working hard", busiest.name),
                        explanation: tr("It is keeping about %1$@ of one processor core busy. That is fine if you are waiting for it to finish something. If you are not, it may be stuck, and quitting it and opening it again usually fixes that.", percent(typical / 100)),
                        suggestion: nil
                    )
                ]
            }
        }
        return []
    }

    private static func heatAndPower(_ sample: PerformanceSample) -> [Diagnosis] {
        var found: [Diagnosis] = []
        if sample.thermal == .hot {
            found.append(
                Diagnosis(
                    id: "running-hot",
                    level: .attention,
                    title: tr("This Mac is running hot"),
                    explanation: tr("macOS is slowing the processor down to cool off, and speeds up again by itself once it has. Heavy apps, direct sunlight and blocked air vents are the usual causes."),
                    suggestion: nil
                )
            )
        }
        if sample.isLowPowerMode {
            found.append(
                Diagnosis(
                    id: "low-power-mode",
                    level: .note,
                    title: tr("Low Power Mode is on"),
                    explanation: tr("It saves energy by making the Mac a little slower. You can turn it off in System Settings, under Battery."),
                    suggestion: nil
                )
            )
        }
        return found
    }

    private static func battery(_ sample: PerformanceSample) -> [Diagnosis] {
        guard let battery = sample.battery, let health = battery.healthPercent, health < 80 else {
            return []
        }
        let explanation: String
        if let cycles = battery.cycleCount {
            explanation = tr("It holds about %1$@ of what it did when new, after %2$@ charge cycles. The Mac works normally, but runs for a shorter time away from power.", percent(Double(health) / 100), "\(cycles)")
        } else {
            explanation = tr("It holds about %1$@ of what it did when new. The Mac works normally, but runs for a shorter time away from power.", percent(Double(health) / 100))
        }
        return [
            Diagnosis(
                id: "battery-aged",
                level: .note,
                title: tr("The battery has aged"),
                explanation: explanation,
                suggestion: nil
            )
        ]
    }

    // MARK: - Wording helpers

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// A share written out for people, for example "85%" or "85 %" depending on the region.
    static func percent(_ fraction: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: fraction)) ?? "\(Int((fraction * 100).rounded()))%"
    }
}
