import Foundation

/// What programs with one name are using right now. Programs that run as several
/// processes under the same name, such as a browser's helpers, are added together.
public struct ProcessUsage: Equatable, Identifiable, Sendable {
    /// The program's name as macOS reports it.
    public let name: String
    /// Processor use as a percentage of one core, so it can go above 100.
    public let cpuPercent: Double
    /// Memory in use, in bytes.
    public let memoryBytes: Int64
    /// How many processes with this name are running.
    public let count: Int

    public var id: String { name }

    public init(name: String, cpuPercent: Double, memoryBytes: Int64, count: Int = 1) {
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.count = count
    }
}

/// How the Mac's memory is being used.
public struct MemoryUsage: Equatable, Sendable {
    /// How hard macOS has to work to give apps the memory they ask for. This says more
    /// about speed than the amount in use, because macOS fills spare memory on purpose.
    public enum Pressure: Int, Sendable {
        case normal
        case elevated
        case high
    }

    /// Installed memory, in bytes.
    public let totalBytes: Int64
    /// Memory apps and macOS are holding on to, in bytes.
    public let usedBytes: Int64
    /// The part of the used memory that macOS has squeezed to make room, in bytes.
    public let compressedBytes: Int64
    /// Data moved out of memory onto the disk, in bytes.
    public let swapUsedBytes: Int64
    public let pressure: Pressure

    public init(totalBytes: Int64, usedBytes: Int64, compressedBytes: Int64, swapUsedBytes: Int64, pressure: Pressure) {
        self.totalBytes = totalBytes
        self.usedBytes = usedBytes
        self.compressedBytes = compressedBytes
        self.swapUsedBytes = swapUsedBytes
        self.pressure = pressure
    }

    /// How much of the installed memory is in use, from 0 to 1.
    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, max(0, Double(usedBytes) / Double(totalBytes)))
    }
}

/// The state of the battery in a portable Mac.
public struct BatteryStatus: Equatable, Sendable {
    /// Charge from 0 to 100.
    public let chargePercent: Int
    public let isCharging: Bool
    public let isPluggedIn: Bool
    /// Minutes until empty, or until full while charging, when macOS has an estimate.
    public let minutesRemaining: Int?
    /// How many full charges the battery has been through.
    public let cycleCount: Int?
    /// How much charge the battery holds compared with when it was new, from 0 to 100.
    public let healthPercent: Int?

    public init(
        chargePercent: Int,
        isCharging: Bool,
        isPluggedIn: Bool,
        minutesRemaining: Int?,
        cycleCount: Int?,
        healthPercent: Int?
    ) {
        self.chargePercent = chargePercent
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.cycleCount = cycleCount
        self.healthPercent = healthPercent
    }
}

/// How warm the Mac is, as far as it affects speed.
public enum ThermalLevel: Int, Sendable {
    case normal
    /// Warm, but not slowed down.
    case warm
    /// Hot enough that macOS slows the processor down to cool off.
    case hot
}

/// A reading of how the Mac is doing at one moment. Taking one never changes anything.
public struct PerformanceSample: Equatable, Sendable {
    public let date: Date
    /// How busy all processor cores are together, from 0 to 1. Unknown for the first reading.
    public let cpuUsedFraction: Double?
    public let coreCount: Int
    public let memory: MemoryUsage?
    /// The programs using the most processor time, busiest first.
    public let topByCPU: [ProcessUsage]
    /// The programs using the most memory, largest first.
    public let topByMemory: [ProcessUsage]
    /// `nil` on a Mac without a battery.
    public let battery: BatteryStatus?
    public let thermal: ThermalLevel
    public let isLowPowerMode: Bool
    public let diskTotalBytes: Int64?
    public let diskAvailableBytes: Int64?
    public let uptimeSeconds: TimeInterval

    public init(
        date: Date,
        cpuUsedFraction: Double?,
        coreCount: Int,
        memory: MemoryUsage?,
        topByCPU: [ProcessUsage],
        topByMemory: [ProcessUsage],
        battery: BatteryStatus?,
        thermal: ThermalLevel,
        isLowPowerMode: Bool,
        diskTotalBytes: Int64?,
        diskAvailableBytes: Int64?,
        uptimeSeconds: TimeInterval
    ) {
        self.date = date
        self.cpuUsedFraction = cpuUsedFraction
        self.coreCount = coreCount
        self.memory = memory
        self.topByCPU = topByCPU
        self.topByMemory = topByMemory
        self.battery = battery
        self.thermal = thermal
        self.isLowPowerMode = isLowPowerMode
        self.diskTotalBytes = diskTotalBytes
        self.diskAvailableBytes = diskAvailableBytes
        self.uptimeSeconds = uptimeSeconds
    }

    /// How much of the startup disk is free, from 0 to 1, or `nil` when unknown.
    public var diskFreeFraction: Double? {
        guard let total = diskTotalBytes, total > 0, let available = diskAvailableBytes else {
            return nil
        }
        return min(1, max(0, Double(available) / Double(total)))
    }
}
