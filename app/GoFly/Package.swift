// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GoFly",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "GoFlyCore", targets: ["GoFlyCore"])],
    targets: [
        .target(name: "GoFlyCore"),
        .testTarget(name: "GoFlyCoreTests", dependencies: ["GoFlyCore"])
    ]
)
