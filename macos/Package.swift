// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WishingWillow",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "WishingWillow",
            path: "Sources/WishingWillow",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "WishingWillowTests",
            dependencies: ["WishingWillow"],
            path: "Tests/WishingWillowTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
