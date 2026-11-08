// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoreasCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "BoreasCore", targets: ["BoreasCore"]),
        .executable(name: "boreasctl", targets: ["boreasctl"]),
    ],
    targets: [
        .target(name: "CIOHID"),
        .target(
            name: "BoreasCore",
            dependencies: ["CIOHID"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "boreasctl", dependencies: ["BoreasCore"]),
        .testTarget(name: "BoreasCoreTests", dependencies: ["BoreasCore"]),
    ]
)
