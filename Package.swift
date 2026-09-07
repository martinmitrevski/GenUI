// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GenUI",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "GenUI",
            targets: ["GenUI"]
        ),
        .library(
            name: "A2uiSampleAgent",
            targets: ["A2uiSampleAgent"]
        ),
        .executable(
            name: "a2ui-sample-server",
            targets: ["A2uiSampleServer"]
        )
    ],
    targets: [
        .target(
            name: "GenUI",
            path: "GenUI/Sources"
        ),
        .testTarget(
            name: "GenUITests",
            dependencies: ["GenUI"],
            path: "GenUITests"
        ),
        .target(
            name: "A2uiSampleAgent",
            dependencies: ["GenUI"],
            path: "SampleBackend/Sources/A2uiSampleAgent",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "A2uiSampleServer",
            dependencies: ["A2uiSampleAgent"],
            path: "SampleBackend/Sources/A2uiSampleServer"
        ),
        .testTarget(
            name: "A2uiSampleAgentTests",
            dependencies: ["A2uiSampleAgent"],
            path: "SampleBackend/Tests/A2uiSampleAgentTests"
        )
    ]
)
