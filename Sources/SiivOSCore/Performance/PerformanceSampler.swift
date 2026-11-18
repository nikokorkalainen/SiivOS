import Foundation

/// How much work the processor has done since the Mac started, in the system's own units.
/// Two readings a moment apart show how busy it was in between.
struct CPUTicks: Equatable {
    let busy: UInt64
    let idle: UInt64

    /// How busy the processor was between two readings, from 0 to 1.
    static func usedFraction(from earlier: CPUTicks, to later: CPUTicks) -> Double? {
        guard later.busy >= earlier.busy, later.idle >= earlier.idle else {
            return nil
        }
        let busy = later.busy - earlier.busy
        let idle = later.idle - earlier.idle
        guard busy + idle > 0 else {
            return nil
        }
        return Double(busy) / Double(busy + idle)
    }

    /// Reads the counters from macOS. Not available elsewhere.
    static func current() -> CPUTicks? {
        #if os(macOS)
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        // The four counters are: user, system, idle, and low-priority ("nice") work.
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        return CPUTicks(busy: user + system + nice, idle: idle)
        #else
        return nil
        #endif
    }
}

/// Runs one of macOS's own command-line tools and returns what it printed.
enum SystemCommand {
    /// - Returns: The tool's output, or `nil` when it is missing or could not be run.
    static func output(of path: String, _ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        // Ask for plain, unlocalised output so numbers always use a decimal point.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Takes readings of how the Mac is doing. Only reads; never changes anything.
///
/// Keep one sampler and call `sample()` every few seconds: processor use is worked out
/// from the difference between one reading and the next.
public final class PerformanceSampler: @unchecked Sendable {
    private let lock = NSLock()
    private var previousTicks: CPUTicks?
    private var batteryHealth: (cycleCount: Int?, healthPercent: Int?) = (nil, nil)
    private var batteryHealthReadAt: Date?

    /// How many programs to list as the biggest users of processor time and of memory.
    private let topCount: Int

    public init(topCount: Int = 5) {
        self.topCount = topCount
    }

    public func sample() -> PerformanceSample {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        let info = ProcessInfo.processInfo

        let ticks = CPUTicks.current()
        var cpuFraction: Double?
        if let ticks, let previousTicks {
            cpuFraction = CPUTicks.usedFraction(from: previousTicks, to: ticks)
        }
        previousTicks = ticks

        let processes = PerformanceParsers.processes(
            fromPS: SystemCommand.output(of: "/bin/ps", ["-Aco", "pid=,pcpu=,rss=,comm="]) ?? ""
        )

        let disk = Self.readStartupDisk()
        return PerformanceSample(
            date: now,
            cpuUsedFraction: cpuFraction,
            coreCount: info.activeProcessorCount,
            memory: readMemory(totalBytes: Int64(clamping: info.physicalMemory)),
            topByCPU: Array(
                processes
                    .filter { $0.cpuPercent >= 0.5 }
                    .sorted { $0.cpuPercent > $1.cpuPercent }
                    .prefix(topCount)
            ),
            topByMemory: Array(processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(topCount)),
            battery: readBattery(now: now),
            thermal: Self.readThermalLevel(),
            isLowPowerMode: Self.readLowPowerMode(),
            diskTotalBytes: disk.total,
            diskAvailableBytes: disk.available,
            uptimeSeconds: info.systemUptime
        )
    }

    private func readMemory(totalBytes: Int64) -> MemoryUsage? {
        guard let vmStat = SystemCommand.output(of: "/usr/bin/vm_stat", []) else {
            return nil
        }
        let swap = SystemCommand.output(of: "/usr/sbin/sysctl", ["-n", "vm.swapusage"])
        let pressure = SystemCommand.output(of: "/usr/sbin/sysctl", ["-n", "kern.memorystatus_vm_pressure_level"])
        return PerformanceParsers.memory(
            fromVMStat: vmStat,
            totalBytes: totalBytes,
            swapUsedBytes: swap.flatMap(PerformanceParsers.swapUsedBytes(fromSysctl:)) ?? 0,
            pressure: pressure.map(PerformanceParsers.pressure(fromSysctl:)) ?? .normal
        )
    }

    private func readBattery(now: Date) -> BatteryStatus? {
        guard let pmset = SystemCommand.output(of: "/usr/bin/pmset", ["-g", "batt"]),
              pmset.contains("InternalBattery")
        else {
            return nil
        }
        // Cycle count and health change slowly, so read them once a minute at most.
        if batteryHealthReadAt.map({ now.timeIntervalSince($0) > 60 }) ?? true {
            if let ioreg = SystemCommand.output(of: "/usr/sbin/ioreg", ["-rn", "AppleSmartBattery"]) {
                batteryHealth = PerformanceParsers.batteryHealth(fromIOReg: ioreg)
            }
            batteryHealthReadAt = now
        }
        return PerformanceParsers.battery(fromPMSet: pmset, health: batteryHealth)
    }

    private static func readThermalLevel() -> ThermalLevel {
        #if os(macOS)
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return .normal
        case .fair: return .warm
        case .serious, .critical: return .hot
        @unknown default: return .normal
        }
        #else
        return .normal
        #endif
    }

    private static func readLowPowerMode() -> Bool {
        #if os(macOS)
        return ProcessInfo.processInfo.isLowPowerModeEnabled
        #else
        return false
        #endif
    }

    private static func readStartupDisk() -> (total: Int64?, available: Int64?) {
        let snapshot = SystemSnapshot.current()
        return (snapshot.diskTotalBytes, snapshot.diskAvailableBytes)
    }
}
