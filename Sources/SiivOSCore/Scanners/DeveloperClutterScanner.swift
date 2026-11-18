import Foundation

/// Finds the data that tools for making software pile up in the home folder: Xcode's
/// build results and simulators, packages downloaded by npm, Gradle and others, and
/// Docker's disk.
///
/// Each place is known by name, so every item says exactly what it is and gets its own
/// label. What a tool simply fetches or builds again is safe to remove. What can hold
/// work that does not come back, such as archived builds or Docker's volumes, is to be
/// checked first. Like every scanner, this one only looks.
public struct DeveloperClutterScanner: SystemScanner {
    public let id = "developer"
    public var title: String { tr("Developer tools") }
    public var summary: String {
        tr("Data kept by tools for making software: build results, downloaded packages and simulators. Most of it is fetched or built again when needed, which makes the next build slower.")
    }

    /// One place a tool keeps data, inside the home folder.
    private struct Place {
        let path: String
        let name: String
        let explanation: String
        let safety: Finding.Safety
        let reason: String
        /// Identifiers of the apps that use this place. While one is open, the item is held back.
        var usedBy: [String] = []
    }

    private static let xcode = "com.apple.dt.xcode"
    private static let simulator = "com.apple.iphonesimulator"
    private static let docker = "com.docker.docker"

    private static var places: [Place] {
        var result = [
            Place(
                path: "Library/Developer/Xcode/DerivedData",
                name: tr("Xcode build results"),
                explanation: tr("What Xcode has built and indexed for your projects."),
                safety: .safeToRemove,
                reason: tr("Xcode builds it again when you next open a project. That first build takes longer."),
                usedBy: [xcode]
            ),
            Place(
                path: "Library/Developer/Xcode/Archives",
                name: tr("Xcode archives"),
                explanation: tr("The builds of your apps that you archived, usually to send them out."),
                safety: .checkFirst,
                reason: tr("An archive is needed to read crash reports for that version or to export it again. It does not come back by itself.")
            )
        ]
        for system in ["iOS", "watchOS", "tvOS"] {
            result.append(
                Place(
                    path: "Library/Developer/Xcode/\(system) DeviceSupport",
                    name: tr("Xcode device files (%1$@)", system),
                    explanation: tr("Files Xcode copied from devices you connected, one set for each system version."),
                    safety: .safeToRemove,
                    reason: tr("Xcode copies them again the next time you connect the device."),
                    usedBy: [xcode]
                )
            )
        }
        result += [
            Place(
                path: "Library/Developer/CoreSimulator/Caches",
                name: tr("Simulator caches"),
                explanation: tr("Temporary files of the iPhone and iPad simulators."),
                safety: .safeToRemove,
                reason: tr("The simulators make them again when they next start."),
                usedBy: [xcode, simulator]
            ),
            Place(
                path: "Library/Developer/CoreSimulator/Devices",
                name: tr("Simulators"),
                explanation: tr("Every iPhone and iPad simulator, with the apps and data inside them."),
                safety: .checkFirst,
                reason: tr("Removing this removes all simulators and what you put in them. Xcode can remove just the ones it no longer supports, which is gentler."),
                usedBy: [xcode, simulator]
            ),
            Place(
                path: ".npm/_cacache",
                name: tr("npm packages"),
                explanation: tr("Packages npm has downloaded for JavaScript projects."),
                safety: .safeToRemove,
                reason: tr("The tool downloads them again when a project needs them.")
            ),
            Place(
                path: ".gradle/caches",
                name: tr("Gradle packages"),
                explanation: tr("Packages and build results Gradle keeps for Java and Android projects."),
                safety: .safeToRemove,
                reason: tr("The tool downloads them again when a project needs them.")
            ),
            Place(
                path: ".cocoapods/repos",
                name: tr("CocoaPods package lists"),
                explanation: tr("CocoaPods' own copy of the lists of available packages."),
                safety: .safeToRemove,
                reason: tr("The tool downloads them again when a project needs them.")
            ),
            Place(
                path: ".cargo/registry",
                name: tr("Cargo packages"),
                explanation: tr("Packages Cargo has downloaded for Rust projects."),
                safety: .safeToRemove,
                reason: tr("The tool downloads them again when a project needs them.")
            ),
            Place(
                path: "go/pkg/mod",
                name: tr("Go packages"),
                explanation: tr("Packages Go has downloaded."),
                safety: .safeToRemove,
                reason: tr("The tool downloads them again when a project needs them.")
            ),
            Place(
                path: ".m2/repository",
                name: tr("Maven packages"),
                explanation: tr("Packages Maven has downloaded for Java projects, and any you built and installed there yourself."),
                safety: .checkFirst,
                reason: tr("Downloaded packages come back by themselves, but ones you built and installed yourself do not.")
            ),
            Place(
                path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw",
                name: tr("Docker's disk"),
                explanation: tr("One file that holds every Docker image, container and volume."),
                safety: .checkFirst,
                reason: tr("Removing it empties Docker completely, including volumes with your data. To free space and keep the volumes, use Docker's own clean-up."),
                usedBy: [docker]
            )
        ]
        return result
    }

    private let homeDirectory: URL
    private let minimumBytes: Int64
    private let runningApps: [RunningApp]

    /// - Parameters:
    ///   - minimumBytes: Smaller items are not reported, because removing them frees next to nothing.
    ///   - runningApps: The apps that are open right now. What they are using is held back.
    public init(
        homeDirectory: URL = URL(fileURLWithPath: NSHomeDirectory()),
        minimumBytes: Int64 = 10_000_000,
        runningApps: [RunningApp] = []
    ) {
        self.homeDirectory = homeDirectory
        self.minimumBytes = minimumBytes
        self.runningApps = runningApps
    }

    public func scan() throws -> [Finding] {
        let fileManager = FileManager.default
        var findings: [Finding] = []
        for place in Self.places {
            let url = homeDirectory.appendingPathComponent(place.path)
            guard (try? fileManager.attributesOfItem(atPath: url.path)) != nil else {
                continue
            }
            let size = FileSize.onDisk(of: url, fileManager: fileManager)
            guard size >= minimumBytes else {
                continue
            }
            let openApp = runningApps.first { app in
                guard let identifier = app.bundleIdentifier?.lowercased() else {
                    return false
                }
                return place.usedBy.contains(identifier)
            }
            findings.append(
                Finding(
                    url: url,
                    sizeBytes: size,
                    explanation: place.explanation,
                    safety: place.safety,
                    safetyReason: place.reason,
                    heldBackReason: openApp.map { tr("%1$@ is open. Quit it, then scan again.", $0.name) },
                    displayName: place.name
                )
            )
        }
        return findings
    }
}
