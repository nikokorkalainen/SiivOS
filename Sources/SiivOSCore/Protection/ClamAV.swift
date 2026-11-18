import Foundation

/// What SiivOS found out about the ClamAV installed on this Mac.
public struct ClamAVStatus: Equatable, Sendable {
    /// Where the scanner program is.
    public let scannerPath: String
    /// Where the program that downloads definitions is, if it was found.
    public let updaterPath: String?
    /// The scanner's version, for example "1.4.1".
    public let engineVersion: String?
    /// The version of the downloaded virus definitions, or `nil` when there are none yet.
    public let definitionsVersion: String?
    /// When those definitions were published.
    public let definitionsDate: Date?

    /// True once definitions have been downloaded, without which nothing can be scanned.
    public var hasDefinitions: Bool {
        definitionsVersion != nil || definitionsDate != nil
    }
}

/// A file ClamAV identified as malware. Detections can be wrong.
public struct MalwareDetection: Equatable, Identifiable, Sendable {
    public let path: String
    /// ClamAV's name for what it thinks the file is.
    public let name: String

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }
}

/// How a scan went.
public struct MalwareScanResult: Equatable, Sendable {
    /// How many files were looked at, when ClamAV reported it.
    public let scannedFiles: Int?
    public let detections: [MalwareDetection]
    /// Why the scan could not finish, if it could not.
    public let problem: String?
    /// True when the user stopped the scan.
    public let wasCancelled: Bool

    /// The same result without the detections whose files are no longer where they
    /// were, for use after some of them have been removed. Read-only.
    public func removingDetectionsNoLongerOnDisk(fileManager: FileManager = .default) -> MalwareScanResult {
        MalwareScanResult(
            scannedFiles: scannedFiles,
            detections: detections.filter { (try? fileManager.attributesOfItem(atPath: $0.path)) != nil },
            problem: problem,
            wasCancelled: wasCancelled
        )
    }
}

/// Uses a ClamAV that the user installed themselves to scan files for malware.
///
/// SiivOS ships no part of ClamAV. If its programs are on the Mac, for example from
/// Homebrew, SiivOS runs them. Virus definitions are kept in SiivOS's own folder and are
/// downloaded only when the user asks, which is the one time SiivOS causes any network use.
/// Scanning only reads; removing a detected file goes through `SafetyCore` like any removal.
public final class ClamAV: @unchecked Sendable {
    private let dataDirectory: URL
    private let searchDirectories: [String]
    private let fileManager = FileManager.default

    private let lock = NSLock()
    private var runningProcess: Process?
    private var cancelRequested = false

    /// Where ClamAV's programs are usually installed: Homebrew on Apple silicon and Intel,
    /// MacPorts, and ClamAV's own installer.
    public static let standardSearchDirectories = [
        "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin", "/usr/local/clamav/bin"
    ]

    /// - Parameters:
    ///   - dataDirectory: Where the virus definitions are kept. Created when needed.
    ///   - searchDirectories: Where to look for ClamAV's programs.
    public init(dataDirectory: URL, searchDirectories: [String] = ClamAV.standardSearchDirectories) {
        self.dataDirectory = dataDirectory
        self.searchDirectories = searchDirectories
    }

    /// The ClamAV helper the app uses, keeping definitions in
    /// `~/Library/Application Support/SiivOS/ClamAV`.
    public static func standard() -> ClamAV {
        let support = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return ClamAV(dataDirectory: support.appendingPathComponent("SiivOS/ClamAV", isDirectory: true))
    }

    // MARK: - Status

    /// Looks for ClamAV and its definitions. Returns `nil` when ClamAV is not installed.
    public func status() -> ClamAVStatus? {
        guard let scanner = locate("clamscan") else {
            return nil
        }
        let versionText = run(scanner, ["--database=\(dataDirectory.path)", "--version"])?.output ?? ""
        let version = Self.parseVersion(versionText)

        // The version line only mentions definitions when they loaded; the files
        // themselves are the fallback.
        var definitionsDate = version.definitionsDate
        if definitionsDate == nil {
            definitionsDate = newestDefinitionsFileDate()
        }
        return ClamAVStatus(
            scannerPath: scanner,
            updaterPath: locate("freshclam"),
            engineVersion: version.engine,
            definitionsVersion: version.definitions,
            definitionsDate: definitionsDate
        )
    }

    private func locate(_ program: String) -> String? {
        searchDirectories
            .map { $0 + "/" + program }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }

    private func newestDefinitionsFileDate() -> Date? {
        let names = ["daily.cvd", "daily.cld", "main.cvd", "main.cld"]
        let dates = names.compactMap { name -> Date? in
            let path = dataDirectory.appendingPathComponent(name).path
            return (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        }
        return dates.max()
    }

    /// Reads what `clamscan --version` prints: "ClamAV 1.4.1/27450/Tue Nov 17 09:35:12 2026",
    /// or just "ClamAV 1.4.1" when no definitions are installed.
    static func parseVersion(_ output: String) -> (engine: String?, definitions: String?, definitionsDate: Date?) {
        guard let line = output.split(whereSeparator: { $0.isNewline }).first(where: { $0.hasPrefix("ClamAV ") }) else {
            return (nil, nil, nil)
        }
        let parts = line.dropFirst("ClamAV ".count).split(separator: "/", maxSplits: 2).map(String.init)
        let engine = parts.first.flatMap { $0.isEmpty ? nil : $0 }
        guard parts.count == 3 else {
            return (engine, nil, nil)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let dateText = parts[2].split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return (engine, parts[1], formatter.date(from: dateText))
    }

    // MARK: - Definitions

    /// Downloads the current virus definitions from ClamAV's servers into SiivOS's folder.
    /// This uses the network, and is only ever called because the user asked.
    ///
    /// - Returns: A description of what went wrong, or `nil` when it worked.
    public func updateDefinitions() -> String? {
        guard let updater = locate("freshclam") else {
            return tr("ClamAV's updater (freshclam) was not found next to the scanner.")
        }
        do {
            try fileManager.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
            // The updater needs a settings file. SiivOS writes its own, so nothing depends
            // on how ClamAV was set up on this Mac.
            let settings = "# Written by SiivOS. Where ClamAV's updater fetches virus definitions.\nDatabaseMirror database.clamav.net\n"
            try Data(settings.utf8).write(to: settingsFile, options: .atomic)
        } catch {
            return error.localizedDescription
        }

        guard let result = run(updater, ["--config-file=\(settingsFile.path)", "--datadir=\(dataDirectory.path)", "--stdout"]) else {
            return tr("ClamAV's updater could not be started.")
        }
        if result.status == 0 {
            return nil
        }
        return tr("The definitions could not be downloaded: %1$@", Self.lastMeaningfulLine(of: result.output))
    }

    private var settingsFile: URL {
        dataDirectory.appendingPathComponent("freshclam.conf")
    }

    // MARK: - Scanning

    /// Scans the given files and folders, including everything inside the folders.
    /// This can take a long time; `cancel()` stops it from another thread.
    public func scan(_ urls: [URL]) -> MalwareScanResult {
        guard let scanner = locate("clamscan") else {
            return MalwareScanResult(scannedFiles: nil, detections: [], problem: tr("ClamAV is not installed."), wasCancelled: false)
        }
        lock.lock()
        cancelRequested = false
        lock.unlock()

        let arguments = ["--database=\(dataDirectory.path)", "--recursive", "--infected", "--stdout"]
            + urls.map { $0.path }
        guard let result = run(scanner, arguments) else {
            return MalwareScanResult(scannedFiles: nil, detections: [], problem: tr("ClamAV could not be started."), wasCancelled: false)
        }

        lock.lock()
        let wasCancelled = cancelRequested
        lock.unlock()

        let parsed = Self.parseScan(result.output)
        // ClamAV ends with 0 when nothing was found and 1 when something was. Anything
        // else means it could not do its work.
        var problem: String?
        if !wasCancelled, result.status != 0, result.status != 1 {
            problem = tr("ClamAV could not finish the scan: %1$@", Self.lastMeaningfulLine(of: result.output))
        }
        return MalwareScanResult(
            scannedFiles: parsed.scannedFiles,
            detections: parsed.detections,
            problem: problem,
            wasCancelled: wasCancelled
        )
    }

    /// Stops a scan or download that is running.
    public func cancel() {
        lock.lock()
        cancelRequested = true
        let process = runningProcess
        lock.unlock()
        process?.terminate()
    }

    /// Reads what `clamscan --infected` prints: one "path: Name FOUND" line per detection,
    /// then a summary with "Scanned files: 123".
    static func parseScan(_ output: String) -> (scannedFiles: Int?, detections: [MalwareDetection]) {
        var detections: [MalwareDetection] = []
        var scannedFiles: Int?
        for line in output.split(whereSeparator: { $0.isNewline }) {
            if line.hasSuffix(" FOUND"), let separator = line.range(of: ": ", options: .backwards) {
                let name = line[separator.upperBound...].dropLast(" FOUND".count)
                detections.append(MalwareDetection(path: String(line[..<separator.lowerBound]), name: String(name)))
            } else if line.hasPrefix("Scanned files:") {
                scannedFiles = Int(line.dropFirst("Scanned files:".count).trimmingCharacters(in: .whitespaces))
            }
        }
        return (scannedFiles, detections)
    }

    /// The last line that says something, for showing why a tool failed.
    static func lastMeaningfulLine(of output: String) -> String {
        let lines = output
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("---") }
        return lines.last(where: { $0.lowercased().contains("error") }) ?? lines.last ?? tr("no details were given")
    }

    // MARK: - Running a program

    /// Runs one of ClamAV's programs, keeping hold of it so that it can be stopped.
    private func run(_ path: String, _ arguments: [String]) -> (output: String, status: Int32)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        lock.lock()
        runningProcess = process
        lock.unlock()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        lock.lock()
        runningProcess = nil
        lock.unlock()
        return (String(data: data, encoding: .utf8) ?? "", process.terminationStatus)
    }
}
