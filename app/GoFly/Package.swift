// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GoFly",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [
        .library(name: "GoFlyCore", targets: ["GoFlyCore"]),
        .library(name: "GoFlyTransport", targets: ["GoFlyTransport"]),
        .executable(name: "GoFlyTransferValidator", targets: ["GoFlyTransferValidator"])
    ],
    targets: [
        .target(name: "GoFlyCore"),
        .target(name: "GoFlyTransport", dependencies: ["GoFlyCore"]),
        .executableTarget(name: "GoFlyTransferValidator", dependencies: ["GoFlyCore"]),
        .testTarget(name: "GoFlyCoreTests", dependencies: ["GoFlyCore"]),
        .testTarget(name: "GoFlyTransportTests", dependencies: ["GoFlyTransport", "GoFlyCore"])
    ]
)
