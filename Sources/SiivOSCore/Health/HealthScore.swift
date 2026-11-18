import Foundation

/// A health score that explains itself: every point comes from a named part with a
/// plain-language reason, so the number is never a mystery or a scare.
public struct HealthScore: Equatable, Sendable {
    public struct Part: Equatable, Identifiable, Sendable {
        public let id: String
        public let title: String
        public let points: Int
        public let maximum: Int
        /// Why this part got these points.
        public let explanation: String
    }

    public let parts: [Part]

    /// The score from 0 to 100. Parts that do not apply to this Mac, such as the battery
    /// on a desktop, are left out, and the rest is scaled to 100.
    public var total: Int {
        let maximum = parts.reduce(0) { $0 + $1.maximum }
        guard maximum > 0 else { return 100 }
        let points = parts.reduce(0) { $0 + $1.points }
        return Int((Double(points) / Double(maximum) * 100).rounded())
    }
}

/// The facts a health score is worked out from.
public struct HealthFacts: Equatable, Sendable {
    /// How much of the startup disk is free, from 0 to 1.
    public var diskFreeFraction: Double?
    public var memoryPressure: MemoryUsage.Pressure?
    /// Identifiers of macOS's own protections that are switched off, for example "filevault".
    public var protectionsOff: [String]
    /// How many things the protection check marked as needing a closer look.
    public var attentionCount: Int
    /// How much the battery holds compared with new, from 0 to 100. `nil` without a battery.
    public var batteryHealthPercent: Int?

    public init(
        diskFreeFraction: Double?,
        memoryPressure: MemoryUsage.Pressure?,
        protectionsOff: [String],
        attentionCount: Int,
        batteryHealthPercent: Int?
    ) {
        self.diskFreeFraction = diskFreeFraction
        self.memoryPressure = memoryPressure
        self.protectionsOff = protectionsOff
        self.attentionCount = attentionCount
        self.batteryHealthPercent = batteryHealthPercent
    }
}

/// Works out the health score. The rules are few and honest: what counts is what really
/// affects a Mac. Free disk space weighs most, a firewall that is off costs nothing
/// because that is macOS's own default, and memory merely being in use is not counted.
public enum HealthScoring {
    public static func score(for facts: HealthFacts) -> HealthScore {
        var parts: [HealthScore.Part] = []

        if let free = facts.diskFreeFraction {
            let percent = PerformanceDiagnosis.percent(free)
            let points: Int
            if free >= 0.20 {
                points = 40
            } else if free <= 0.05 {
                points = 0
            } else {
                points = Int(((free - 0.05) / 0.15 * 40).rounded())
            }
            parts.append(
                HealthScore.Part(
                    id: "disk",
                    title: tr("Disk space"),
                    points: points,
                    maximum: 40,
                    explanation: free >= 0.20
                        ? tr("%1$@ of the startup disk is free, which is plenty.", percent)
                        : tr("Only %1$@ of the startup disk is free. A Mac works best with at least a fifth free, and Cleanup can help.", percent)
                )
            )
        }

        if let pressure = facts.memoryPressure {
            let points: Int
            let explanation: String
            switch pressure {
            case .normal:
                points = 15
                explanation = tr("Memory has room to spare right now.")
            case .elevated:
                points = 8
                explanation = tr("Memory is getting tight right now.")
            case .high:
                points = 0
                explanation = tr("Memory is under heavy pressure right now.")
            }
            parts.append(
                HealthScore.Part(id: "memory", title: tr("Memory"), points: points, maximum: 15, explanation: explanation)
            )
        }

        // The firewall is left out on purpose: off is the macOS default.
        let penalties = ["gatekeeper": 10, "system-integrity-protection": 10, "filevault": 5]
        let counted = facts.protectionsOff.filter { penalties[$0] != nil }
        let lost = counted.reduce(0) { $0 + (penalties[$1] ?? 0) }
        parts.append(
            HealthScore.Part(
                id: "protection",
                title: tr("Protection built into macOS"),
                points: max(0, 25 - lost),
                maximum: 25,
                explanation: counted.isEmpty
                    ? tr("Gatekeeper, System Integrity Protection and FileVault are all on.")
                    : tr("Turned off: %1$@.", counted.map(protectionName).joined(separator: ", "))
            )
        )

        let attention = max(0, facts.attentionCount)
        let attentionText: String
        if attention == 0 {
            attentionText = tr("Nothing on this Mac needs a closer look.")
        } else if attention == 1 {
            attentionText = tr("1 thing in Protection needs a closer look.")
        } else {
            attentionText = tr("%1$@ things in Protection need a closer look.", "\(attention)")
        }
        parts.append(
            HealthScore.Part(
                id: "closer-look",
                title: tr("Things needing a closer look"),
                points: max(0, 10 - attention * 5),
                maximum: 10,
                explanation: attentionText
            )
        )

        if let health = facts.batteryHealthPercent {
            let percent = PerformanceDiagnosis.percent(Double(health) / 100)
            let points: Int
            if health >= 80 {
                points = 10
            } else if health <= 60 {
                points = 0
            } else {
                points = Int((Double(health - 60) / 20 * 10).rounded())
            }
            parts.append(
                HealthScore.Part(
                    id: "battery",
                    title: tr("Battery"),
                    points: points,
                    maximum: 10,
                    explanation: health >= 80
                        ? tr("The battery holds %1$@ of what it did when new.", percent)
                        : tr("The battery holds %1$@ of what it did when new, so it runs for a shorter time away from power.", percent)
                )
            )
        }

        return HealthScore(parts: parts)
    }

    /// The name of one of macOS's own protections, from its identifier.
    static func protectionName(_ identifier: String) -> String {
        switch identifier {
        case "gatekeeper": return tr("Gatekeeper")
        case "system-integrity-protection": return tr("System Integrity Protection")
        case "filevault": return tr("FileVault")
        case "firewall": return tr("Firewall")
        default: return identifier
        }
    }
}
