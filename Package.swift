// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Opus",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .library(name: "OpusCore", targets: ["OpusCore"]),
        .executable(name: "Opus", targets: ["Opus"])
    ],
    dependencies: [.package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "OpusCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Opus", dependencies: ["OpusCore", .product(name: "SwiftMath", package: "SwiftMath")]),
        .testTarget(name: "OpusCoreTests", dependencies: ["OpusCore"]),
        .testTarget(name: "OpusTests", dependencies: ["Opus", "OpusCore"])
    ]
)
