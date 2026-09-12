// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "OpusCore", targets: ["OpusCore"]),
    .library(name: "OpusGTKSupport", targets: ["OpusGTKSupport"])
]
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
    .target(name: "OpusCore", dependencies: ["CSQLite"]),
    .target(name: "OpusGTKSupport", dependencies: ["OpusCore"]),
    .testTarget(name: "OpusCoreTests", dependencies: ["OpusCore"], path: "Tests/OpusCoreTests"),
    .testTarget(name: "OpusGTKSupportTests", dependencies: ["OpusGTKSupport", "OpusCore"], path: "Tests/OpusGTKSupportTests")
]
#if os(Linux)
products.append(.executable(name: "opus", targets: ["OpusGTK"]))
targets += [
    .systemLibrary(name: "CGTK", pkgConfig: "gtk4", providers: [.apt(["libgtk-4-dev"])]),
    .target(
        name: "GTKBridge",
        dependencies: ["CGTK"],
        exclude: [],
        resources: [.copy("resources")],
        publicHeadersPath: "include",
        cSettings: [.headerSearchPath("."), .headerSearchPath("include")]
    ),
    .executableTarget(name: "OpusGTK", dependencies: ["OpusCore", "OpusGTKSupport", "GTKBridge"])
]
#else
products.append(.executable(name: "Opus", targets: ["Opus"]))
targets += [
    .executableTarget(name: "Opus", dependencies: ["OpusCore"]),
    .testTarget(name: "OpusTests", dependencies: ["Opus", "OpusCore"])
]
#endif
let package = Package(name: "Opus", platforms: [.macOS(.v14)], products: products, targets: targets)
