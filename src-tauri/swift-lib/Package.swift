// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "swift-lib",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(
            name: "swift-lib",
            type: .static,
            targets: ["swift-lib"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/Brendonovich/swift-rs", from: "1.0.7")
    ],
    targets: [
        .target(
            name: "swift-lib",
            dependencies: [
                .product(name: "SwiftRs", package: "swift-rs")
            ],
            path: "Sources"
        )
    ]
)
