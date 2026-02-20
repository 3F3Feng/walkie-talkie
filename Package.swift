// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WolkieTalkie",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "WolkieTalkie",
            targets: ["WolkieTalkie"]
        ),
    ],
    dependencies: [
        .package(name: "WalkieTalkieCore", path: "/Users/shifengzhang/.openclaw/workspace")
    ],
    targets: [
        .target(
            name: "WolkieTalkie",
            dependencies: [
                .product(name: "Bridge", package: "WalkieTalkieCore"),
                .product(name: "Core", package: "WalkieTalkieCore"),
                .product(name: "Managers", package: "WalkieTalkieCore"),
                .product(name: "Protocols", package: "WalkieTalkieCore")
            ],
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
