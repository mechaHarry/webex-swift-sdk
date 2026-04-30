// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "webex-spaces-list-smoke",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "WebexSpacesListSmoke",
            dependencies: [
                .product(name: "WebexSwiftSDK", package: "webex-swift-sdk")
            ]
        ),
        .testTarget(
            name: "WebexSpacesListSmokeTests",
            dependencies: ["WebexSpacesListSmoke"]
        )
    ]
)
