// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-realtime-events-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexRealtimeEventsSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexRealtimeEventsSmokeTests",
            dependencies: ["WebexRealtimeEventsSmoke"]
        )
    ]
)
