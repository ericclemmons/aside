// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aside",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "AsideCore",
            path: "Sources/AsideCore"
        ),
        .executableTarget(
            name: "Aside",
            dependencies: [
                "AsideCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/Aside",
            exclude: ["Aside.entitlements", "Info.plist"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "AsideTests",
            dependencies: ["AsideCore"],
            path: "Tests/AsideTests"
        ),
    ]
)
