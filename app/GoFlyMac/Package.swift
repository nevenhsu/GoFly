// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GoFlyMac",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "GoFlyMac", targets: ["GoFlyMac"])],
    targets: [
        .target(name: "GoFlyMacCore"),
        .executableTarget(name: "GoFlyMac", dependencies: ["GoFlyMacCore"], resources: [.process("Resources")]),
        .testTarget(name: "GoFlyMacCoreTests", dependencies: ["GoFlyMacCore"])
    ]
)
