// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-messages-stream-window-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexMessagesStreamWindowSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexMessagesStreamWindowSmokeTests",
            dependencies: ["WebexMessagesStreamWindowSmoke"]
        )
    ]
)
