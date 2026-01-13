// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebClient",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "WebClient",
            targets: ["WebClient"]
        ),
    ],
    targets: [
        .target(
            name: "WebClient",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(
            name: "WebClientTests",
            dependencies: ["WebClient"]
        ),
    ]
)
