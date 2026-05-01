// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-memberships-list-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexMembershipsListSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexMembershipsListSmokeTests",
            dependencies: ["WebexMembershipsListSmoke"]
        )
    ]
)
