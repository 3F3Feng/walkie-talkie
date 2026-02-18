// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "WolkieTalkie",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "WolkieTalkie",
            targets: ["WolkieTalkie"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WolkieTalkie",
            dependencies: [],
            path: "Sources"
        ),
    ]
)
