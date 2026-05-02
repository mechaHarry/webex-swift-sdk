// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-messages-list-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexMessagesListSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexMessagesListSmokeTests",
            dependencies: ["WebexMessagesListSmoke"]
        )
    ]
)
