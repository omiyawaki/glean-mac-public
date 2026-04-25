// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GleanMac",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "GleanMac",
            path: "Sources/GleanMac"
        )
    ]
)
