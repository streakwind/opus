// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Opus",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Opus", targets: ["Opus"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .executableTarget(name: "Opus", dependencies: ["CSQLite"]),
        .testTarget(name: "OpusTests", dependencies: ["Opus"])
    ]
)
