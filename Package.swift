// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockLyrics",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DockLyrics", targets: ["DockLyrics"])
    ],
    targets: [
        .executableTarget(
            name: "DockLyrics",
            path: "Sources/DockLyrics",
            resources: [.process("Resources")]
        )
    ]
)
