// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiivOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SiivOS", targets: ["SiivOS"]),
        // The name must differ from "SiivOS" by more than capital letters: a Mac's disk
        // treats "siivos" and "SiivOS" as the same file name.
        .executable(name: "siivos-cli", targets: ["SiivOSCLI"]),
        .library(name: "SiivOSCore", targets: ["SiivOSCore"])
    ],
    targets: [
        // The app: SwiftUI interface only. No scanning or cleaning logic lives here.
        .executableTarget(
            name: "SiivOS",
            dependencies: ["SiivOSCore"]
        ),
        // The agent door: a read-only command-line tool for AI agents. A few lines that
        // pass the question to the engine.
        .executableTarget(
            name: "SiivOSCLI",
            dependencies: ["SiivOSCore"]
        ),
        // The engine: everything that inspects or changes the Mac. No UI code lives here.
        .target(
            name: "SiivOSCore"
        ),
        .testTarget(
            name: "SiivOSCoreTests",
            dependencies: ["SiivOSCore"]
        )
    ]
)
