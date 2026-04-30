// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-swift-sdk",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WebexSwiftSDK",
            targets: ["WebexSwiftSDK"]
        )
    ],
    targets: [
        .target(
            name: "WebexSwiftSDK"
        ),
        .testTarget(
            name: "WebexSwiftSDKTests",
            dependencies: ["WebexSwiftSDK"]
        )
    ]
)
