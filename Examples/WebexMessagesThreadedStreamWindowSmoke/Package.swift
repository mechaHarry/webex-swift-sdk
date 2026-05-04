// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-messages-threaded-stream-window-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexMessagesThreadedStreamWindowSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexMessagesThreadedStreamWindowSmokeTests",
            dependencies: ["WebexMessagesThreadedStreamWindowSmoke"]
        )
    ]
)
