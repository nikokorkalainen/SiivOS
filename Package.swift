// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SiivOS",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SiivOS", targets: ["SiivOS"]),
        .library(name: "SiivOSCore", targets: ["SiivOSCore"])
    ],
    targets: [
        // The app: SwiftUI interface only. No scanning or cleaning logic lives here.
        .executableTarget(
            name: "SiivOS",
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
