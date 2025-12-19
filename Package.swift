//
// Copyright © 2025 Martin Mitrevski. All rights reserved.
//

// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GenUI",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "GenUI",
            targets: ["GenUI"]
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
        )
    ]
)
