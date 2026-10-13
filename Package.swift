// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Opus",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .library(name: "OpusCore", targets: ["OpusCore"]),
        .library(name: "OpusDesktop", targets: ["OpusDesktop"]),
        .library(name: "OpusMobile", targets: ["OpusMobile"]),
        .executable(name: "Opus", targets: ["Opus"])
    ],
    dependencies: [.package(url: "https://github.com/mgriebling/SwiftMath.git", from: "1.7.3")],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "OpusCore", dependencies: ["CSQLite"]),
        .target(name: "OpusDesktop", dependencies: ["OpusCore", .product(name: "SwiftMath", package: "SwiftMath")], path: "Sources/Opus"),
        .target(name: "OpusMobile", dependencies: ["OpusCore"]),
        .executableTarget(name: "Opus", dependencies: ["OpusDesktop"], path: "Sources/OpusLauncher"),
        .testTarget(name: "OpusCoreTests", dependencies: ["OpusCore"]),
        .testTarget(name: "OpusTests", dependencies: ["OpusDesktop", "OpusCore"])
    ]
)
