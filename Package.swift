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
            path: "Sources/GleanMac",
            resources: [
                // Dark Reader (MIT, https://darkreader.org/) — bundled
                // and injected as a per-frame WKUserScript inside
                // WebViewer to give publisher pages a Noir-style dark
                // theme without relying on a Safari extension we can't
                // load.
                .process("Resources/darkreader.js"),
            ]
        ),
        .testTarget(
            name: "GleanMacTests",
            dependencies: ["GleanMac"],
            path: "Tests/GleanMacTests"
        ),
    ]
)
