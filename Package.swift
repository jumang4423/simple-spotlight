// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleSpotlight",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "SimpleSpotlight",
            path: "Sources/SimpleSpotlight",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SimpleSpotlightTests",
            dependencies: ["SimpleSpotlight"],
            path: "Tests/SimpleSpotlightTests"
        )
    ]
)
