// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LocalGo",
    platforms: [
        .iOS(.v26),
        .macOS(.v15)
    ],
    products: [
        .library(name: "LocalGoCore", targets: ["LocalGoCore"])
    ],
    targets: [
        .target(
            name: "LocalGoCore",
            path: "StikDebug/LocalGo",
            exclude: [
                "LiveLocationEngine.swift",
                "LocalGoPairingIdentity.swift",
                "LocalGoProofView.swift",
                "LocalGoMapView.swift",
                "LocalGoFeatureModel.swift",
                "LocalGoStyle.swift",
                "LocalGoVPNButton.swift",
                "LocalGoCurrentLocation.swift"
            ],
            sources: [
                "LocationCommandCoordinator.swift",
                "LocationClearRecovery.swift",
                "MovementController.swift",
                "DevicePreparationPolicy.swift",
                "FeatureDomain.swift",
                "GPXCodec.swift",
                "LocalPlaceStore.swift",
                "LocalGoSetupProtocol.swift",
                "LocalGoSetupHandoff.swift",
                "LocalGoTunnelMonitor.swift"
            ]
        ),
        .testTarget(
            name: "LocalGoCoreTests",
            dependencies: ["LocalGoCore"],
            path: "Tests/LocalGoCoreTests"
        )
    ]
)
