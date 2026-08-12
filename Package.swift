// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Mimicry",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MimicryCore",
            targets: ["MimicryCore"]
        ),
        .executable(
            name: "mimicry",
            targets: ["MimicryCLI"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "MimicryCore"
        ),
        .executableTarget(
            name: "MimicryCLI",
            dependencies: [
                "MimicryCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MimicryCoreTests",
            dependencies: ["MimicryCore"]
        )
    ]
)
