// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BlockOS",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "BlockOSDomain", targets: ["BlockOSDomain"]),
        .library(name: "BlockOSPersistence", targets: ["BlockOSPersistence"]),
        .library(name: "BlockOSEnforcement", targets: ["BlockOSEnforcement"]),
        .library(name: "BlockOSAppSupport", targets: ["BlockOSAppSupport"])
    ],
    targets: [
        .target(name: "BlockOSDomain"),
        .target(name: "BlockOSPersistence", dependencies: ["BlockOSDomain"]),
        .target(name: "BlockOSEnforcement", dependencies: ["BlockOSDomain"]),
        .target(
            name: "BlockOSAppSupport",
            dependencies: ["BlockOSDomain", "BlockOSPersistence", "BlockOSEnforcement"]
        ),
        .testTarget(name: "BlockOSDomainTests", dependencies: ["BlockOSDomain"]),
        .testTarget(
            name: "BlockOSAppSupportTests",
            dependencies: ["BlockOSAppSupport", "BlockOSDomain", "BlockOSEnforcement", "BlockOSPersistence"]
        )
    ]
)
