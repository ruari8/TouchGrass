// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TouchGrassKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "TouchGrassCore", targets: ["TouchGrassCore"]),
        .library(name: "TouchGrassScreenTime", targets: ["TouchGrassScreenTime"])
    ],
    targets: [
        .target(name: "TouchGrassCore"),
        .target(name: "TouchGrassScreenTime", dependencies: ["TouchGrassCore"]),
        .testTarget(name: "TouchGrassCoreTests", dependencies: ["TouchGrassCore"])
    ]
)
