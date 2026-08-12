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
        .library(
            name: "MimicryCLISupport",
            targets: ["MimicryCLISupport"]
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
        .target(
            name: "MimicryCLISupport",
            dependencies: [
                "MimicryCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "MimicryCLI",
            dependencies: [
                "MimicryCLISupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MimicryCoreTests",
            dependencies: ["MimicryCore"]
        ),
        .testTarget(
            name: "MimicryCLITests",
            dependencies: ["MimicryCLISupport"]
        )
    ]
)
