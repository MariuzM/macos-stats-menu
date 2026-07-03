// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StatsMenu",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "StatsMenu",
            path: "Sources/StatsMenu"
        )
    ]
)
