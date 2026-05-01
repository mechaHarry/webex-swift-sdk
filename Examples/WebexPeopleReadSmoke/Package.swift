// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-people-read-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexPeopleReadSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexPeopleReadSmokeTests",
            dependencies: ["WebexPeopleReadSmoke"]
        )
    ]
)
