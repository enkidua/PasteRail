// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PasteRail",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "PasteRail", targets: ["PasteRail"])
    ],
    targets: [
        .executableTarget(
            name: "PasteRail",
            path: "PasteRail/Sources",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CryptoKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "PasteRailTests",
            dependencies: ["PasteRail"],
            path: "PasteRail/Tests"
        ),
        .testTarget(
            name: "PasteRailKeychainIntegrationTests",
            dependencies: ["PasteRail"],
            path: "PasteRail/KeychainIntegrationTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
