// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WolkieTalkie",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "WolkieTalkie",
            targets: ["WolkieTalkie"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WolkieTalkie",
            dependencies: [],
            path: "Sources/WolkieTalkie",
            exclude: ["ProximityManager_fixes.swift"]
        ),
        .testTarget(
            name: "WolkieTalkieTests",
            dependencies: ["WolkieTalkie"],
            path: "Tests/WolkieTalkieTests"
        ),
    ]
)
