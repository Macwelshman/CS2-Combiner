// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CS2TextureCombiner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CS2TextureCombiner", targets: ["CS2TextureCombiner"])
    ],
    targets: [
        .executableTarget(
            name: "CS2TextureCombiner",
            path: "Sources/CS2TextureCombiner"
        ),
        .testTarget(
            name: "CS2TextureCombinerTests",
            dependencies: ["CS2TextureCombiner"],
            path: "Tests/CS2TextureCombinerTests"
        )
    ]
)
