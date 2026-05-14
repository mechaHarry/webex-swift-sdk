// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-spaces-enriched-snapshot-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexSpacesEnrichedSnapshotSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexSpacesEnrichedSnapshotSmokeTests",
            dependencies: ["WebexSpacesEnrichedSnapshotSmoke"]
        )
    ]
)
