// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClawGotchi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClawGotchi",
            path: "Sources"
        )
    ]
)
