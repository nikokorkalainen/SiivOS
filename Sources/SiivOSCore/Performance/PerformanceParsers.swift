import Foundation

/// Turns the text that macOS's own command-line tools print into numbers.
///
/// Reading the tools' output keeps almost all of this code plain text handling, which
/// can be tested anywhere. Nothing here runs a tool or changes anything.
enum PerformanceParsers {
    // MARK: - Processes (ps)

    /// Reads the output of `ps -Aco pid=,pcpu=,rss=,comm=`: one process per line with its
    /// number, processor use in percent, memory in kilobytes, and name.
    /// Processes with the same name are added together.
    static func processes(fromPS output: String) -> [ProcessUsage] {
        var cpuByName: [String: Double] = [:]
        var memoryByName: [String: Int64] = [:]
        var countByName: [String: Int] = [:]
        var order: [String] = []

        for line in output.split(whereSeparator: { $0.isNewline }) {
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4,
                  Int32(fields[0]) != nil,
                  let cpu = decimal(fields[1]),
                  let kilobytes = Int64(fields[2])
            else {
                continue
            }
            let name = fields[3].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else {
                continue
            }
            if countByName[name] == nil {
                order.append(name)
            }
            cpuByName[name, default: 0] += cpu
            memoryByName[name, default: 0] += kilobytes * 1_024
            countByName[name, default: 0] += 1
        }

        return order.map { name in
            ProcessUsage(
                name: name,
                cpuPercent: cpuByName[name] ?? 0,
                memoryBytes: memoryByName[name] ?? 0,
                count: countByName[name] ?? 1
            )
        }
    }

    // MARK: - Memory (vm_stat and sysctl)

    /// Reads the output of `vm_stat`, together with the swap use and memory pressure
    /// from `sysctl`, into one picture of memory use.
    ///
    /// "In use" follows Activity Monitor: memory apps hold that cannot simply be dropped,
    /// memory macOS itself has locked, and compressed memory.
    static func memory(
        fromVMStat output: String,
        totalBytes: Int64,
        swapUsedBytes: Int64,
        pressure: MemoryUsage.Pressure
    ) -> MemoryUsage? {
        guard let pageSize = pageSize(fromVMStat: output) else {
            return nil
        }
        var pages: [String: Int64] = [:]
        for line in output.split(whereSeparator: { $0.isNewline }) {
            guard let colon = line.firstIndex(of: ":") else {
                continue
            }
            let label = line[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            let digits = line[line.index(after: colon)...].filter { ("0"..."9").contains($0) }
            if let value = Int64(digits) {
                pages[label] = value
            }
        }
        guard let wired = pages["Pages wired down"],
              let compressed = pages["Pages occupied by compressor"]
        else {
            return nil
        }
        // "Anonymous pages" is what apps hold; purgeable pages are the part of it that
        // macOS may take back at any time, so they do not count as in use.
        let anonymous = pages["Anonymous pages"] ?? pages["Pages active"] ?? 0
        let purgeable = pages["Pages purgeable"] ?? 0
        let usedPages = max(0, anonymous - purgeable) + wired + compressed

        return MemoryUsage(
            totalBytes: totalBytes,
            usedBytes: min(totalBytes, usedPages * pageSize),
            compressedBytes: compressed * pageSize,
            swapUsedBytes: swapUsedBytes,
            pressure: pressure
        )
    }

    /// The memory page size from the first line of `vm_stat`: "(page size of 16384 bytes)".
    static func pageSize(fromVMStat output: String) -> Int64? {
        guard let range = output.range(of: "page size of ") else {
            return nil
        }
        let digits = output[range.upperBound...].prefix { ("0"..."9").contains($0) }
        return Int64(digits)
    }

    /// Reads `sysctl -n vm.swapusage`: "total = 2048.00M  used = 1024.50M  free = 1023.50M".
    static func swapUsedBytes(fromSysctl output: String) -> Int64? {
        guard let range = output.range(of: "used = ") else {
            return nil
        }
        let rest = output[range.upperBound...]
        let number = rest.prefix { ("0"..."9").contains($0) || $0 == "." || $0 == "," }
        guard let value = decimal(number) else {
            return nil
        }
        let unit = rest.dropFirst(number.count).first
        switch unit {
        case "K": return Int64(value * 1_024)
        case "M": return Int64(value * 1_048_576)
        case "G": return Int64(value * 1_073_741_824)
        default: return Int64(value)
        }
    }

    /// Reads `sysctl -n kern.memorystatus_vm_pressure_level`: 1 is normal, 2 a warning, 4 critical.
    static func pressure(fromSysctl output: String) -> MemoryUsage.Pressure {
        switch Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case 2: return .elevated
        case 4: return .high
        default: return .normal
        }
    }

    // MARK: - Battery (pmset and ioreg)

    /// Reads `pmset -g batt`. Returns `nil` on a Mac without a battery.
    ///
    ///     Now drawing from 'Battery Power'
    ///      -InternalBattery-0 (id=123)	85%; discharging; 4:12 remaining present: true
    ///
    /// - Parameter health: Cycle count and health read separately from `ioreg`.
    static func battery(fromPMSet output: String, health: (cycleCount: Int?, healthPercent: Int?)) -> BatteryStatus? {
        let lines = output.split(whereSeparator: { $0.isNewline })
        guard let batteryLine = lines.first(where: { $0.contains("InternalBattery") }),
              let percentSign = batteryLine.firstIndex(of: "%")
        else {
            return nil
        }
        let beforePercent = batteryLine[..<percentSign]
        let digits = String(beforePercent.reversed().prefix { ("0"..."9").contains($0) }.reversed())
        guard let charge = Int(digits) else {
            return nil
        }

        let parts = batteryLine[batteryLine.index(after: percentSign)...]
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let state = parts.first ?? ""
        let pluggedIn = lines.first.map { $0.contains("AC Power") } ?? false

        var minutes: Int?
        if let estimate = parts.first(where: { $0.contains("remaining") }),
           let time = estimate.split(separator: " ").first {
            let pieces = time.split(separator: ":")
            if pieces.count == 2, let hours = Int(pieces[0]), let mins = Int(pieces[1]), hours + mins > 0 {
                minutes = hours * 60 + mins
            }
        }

        return BatteryStatus(
            chargePercent: min(100, max(0, charge)),
            isCharging: state == "charging",
            isPluggedIn: pluggedIn,
            minutesRemaining: minutes,
            cycleCount: health.cycleCount,
            healthPercent: health.healthPercent
        )
    }

    /// Reads the battery's cycle count and health from `ioreg -rn AppleSmartBattery`.
    ///
    /// Health is how much the battery holds now compared with its design. macOS's own
    /// "Maximum Capacity" figure is worked out a little differently and can be a few
    /// points off this one.
    static func batteryHealth(fromIOReg output: String) -> (cycleCount: Int?, healthPercent: Int?) {
        func value(_ key: String) -> Int? {
            guard let range = output.range(of: "\"\(key)\" = ") else {
                return nil
            }
            return Int(output[range.upperBound...].prefix { ("0"..."9").contains($0) })
        }

        var health: Int?
        if let design = value("DesignCapacity"), design > 0 {
            // Newer Macs report the real capacity under "AppleRawMaxCapacity" and a plain
            // percentage under "MaxCapacity"; older ones report the capacity as "MaxCapacity".
            let current = value("AppleRawMaxCapacity") ?? value("MaxCapacity").flatMap { $0 > 100 ? $0 : nil }
            if let current {
                health = min(100, max(0, Int((Double(current) / Double(design) * 100).rounded())))
            }
        }
        return (value("CycleCount"), health)
    }

    // MARK: - Helpers

    /// A number written with a point or a comma as its decimal mark.
    private static func decimal<S: StringProtocol>(_ text: S) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
