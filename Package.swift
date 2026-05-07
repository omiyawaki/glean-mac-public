// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GleanMac",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../apple-app-tools")
    ],
    targets: [
        .executableTarget(
            name: "GleanMac",
            dependencies: [
                .product(name: "AppleAppDesignSystem", package: "apple-app-tools"),
                .product(name: "LocalAppUpdateKit", package: "apple-app-tools")
            ],
            path: "Sources/GleanMac"
        ),
        .testTarget(
            name: "GleanMacTests",
            dependencies: ["GleanMac"],
            path: "Tests/GleanMacTests"
        ),
    ]
)
