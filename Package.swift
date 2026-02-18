// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BinauralEngine",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BinauralEngine", targets: ["BinauralEngine"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "BinauralEngine",
            dependencies: [],
            path: "Sources",
            exclude: ["Resources/Info.plist"],
            resources: [
                .copy("Resources")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("MediaPlayer"),
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "BinauralEngineTests",
            dependencies: ["BinauralEngine"],
            path: "Tests"
        )
    ]
)
