// swift-tools-version: 5.9

import Foundation
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
        )
    ]
)
