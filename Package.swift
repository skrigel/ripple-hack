// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ripple",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "Ripple",
            targets: ["Ripple"]
        ),
    ],
    targets: [
        .target(
            name: "Ripple",
            resources: [.process("Assets.xcassets")]
        ),
    ]
)
