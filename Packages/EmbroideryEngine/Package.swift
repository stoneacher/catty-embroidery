// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmbroideryEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EmbroideryEngine", targets: ["EmbroideryEngine"])
    ],
    targets: [
        .target(name: "EmbroideryEngine"),
        .testTarget(
            name: "EmbroideryEngineTests",
            dependencies: ["EmbroideryEngine"],
            // .copy keeps the DST fixtures byte-identical (golden tests diff them byte by byte).
            resources: [.copy("Resources")]
        )
    ],
    swiftLanguageModes: [.v6]
)
