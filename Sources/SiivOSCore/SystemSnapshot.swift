import Foundation

/// A read-only picture of the Mac at one moment in time.
///
/// Taking a snapshot never changes anything on the system.
public struct SystemSnapshot: Equatable, Sendable {
    /// Human-readable macOS version, for example "Version 15.1 (Build 24B83)".
    public let osVersion: String
    /// Number of processor cores available to the system.
    public let processorCount: Int
    /// Installed memory in bytes.
    public let physicalMemoryBytes: UInt64
    /// Seconds since the Mac was last restarted.
    public let uptimeSeconds: TimeInterval
    /// Size of the startup disk in bytes, if it could be read.
    public let diskTotalBytes: Int64?
    /// Space on the startup disk that can be freed up for the user, in bytes, if it could be read.
    public let diskAvailableBytes: Int64?

    public init(
        osVersion: String,
        processorCount: Int,
        physicalMemoryBytes: UInt64,
        uptimeSeconds: TimeInterval,
        diskTotalBytes: Int64?,
        diskAvailableBytes: Int64?
    ) {
        self.osVersion = osVersion
        self.processorCount = processorCount
        self.physicalMemoryBytes = physicalMemoryBytes
        self.uptimeSeconds = uptimeSeconds
        self.diskTotalBytes = diskTotalBytes
        self.diskAvailableBytes = diskAvailableBytes
    }

    /// Bytes in use on the startup disk, or `nil` when the disk could not be read.
    public var diskUsedBytes: Int64? {
        guard let total = diskTotalBytes, let available = diskAvailableBytes else {
            return nil
        }
        return max(0, total - available)
    }

    /// How full the startup disk is, from 0 (empty) to 1 (full), or `nil` when unknown.
    public var diskUsedFraction: Double? {
        guard let total = diskTotalBytes, total > 0, let used = diskUsedBytes else {
            return nil
        }
        return min(1, Double(used) / Double(total))
    }

    /// Reads the current state of this Mac.
    public static func current() -> SystemSnapshot {
        let info = ProcessInfo.processInfo
        let disk = readStartupDisk()
        return SystemSnapshot(
            osVersion: info.operatingSystemVersionString,
            processorCount: info.processorCount,
            physicalMemoryBytes: info.physicalMemory,
            uptimeSeconds: info.systemUptime,
            diskTotalBytes: disk.total,
            diskAvailableBytes: disk.available
        )
    }

    private static func readStartupDisk() -> (total: Int64?, available: Int64?) {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        #if os(macOS)
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? home.resourceValues(forKeys: keys) else {
            return (nil, nil)
        }
        let total = values.volumeTotalCapacity.map { Int64($0) }
        let available = values.volumeAvailableCapacityForImportantUsage
        return (total, available)
        #else
        // Not a Mac. This branch exists only so the engine's tests can also run on
        // Linux (see Scripts/check-engine-on-linux.sh); the app itself is Mac-only.
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]
        guard let values = try? home.resourceValues(forKeys: keys) else {
            return (nil, nil)
        }
        let total = values.volumeTotalCapacity.map { Int64($0) }
        let available = values.volumeAvailableCapacity.map { Int64($0) }
        return (total, available)
        #endif
    }
}
