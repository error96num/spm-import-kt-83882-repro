// swift-tools-version: 6.0
//
// Minimal repro for YouTrack KT-83882
// "Search for a way to reproduce 'Missing package product' in KMP IDE plugin"
// https://youtrack.jetbrains.com/issue/KT-83882

import PackageDescription

let package = Package(
    name: "MinimalBridge",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(
            name: "MinimalBridge",
            targets: ["MinimalBridge"],
        ),
    ],
    targets: [
        .target(
            name: "MinimalBridge",
        ),
    ],
)
