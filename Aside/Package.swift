// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aside",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.12.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.9.0"),
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
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/Aside",
            exclude: ["Aside.entitlements", "Info.plist"],
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
            ]
        ),
        .testTarget(
            name: "AsideTests",
            dependencies: ["AsideCore"],
            path: "Tests/AsideTests"
        ),
    ]
)
