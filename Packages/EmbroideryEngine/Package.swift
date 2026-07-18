// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmbroideryEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EmbroideryEngine", targets: ["EmbroideryEngine"]),
        .library(name: "ProgramModel", targets: ["ProgramModel"]),
        .library(name: "Interpreter", targets: ["Interpreter"])
    ],
    targets: [
        .target(name: "EmbroideryEngine"),
        // ADR-016: the dependency arrow points inward only — ProgramModel depends on
        // nothing, Interpreter is the only place model and engine meet.
        .target(name: "ProgramModel"),
        .target(name: "Interpreter", dependencies: ["ProgramModel", "EmbroideryEngine"]),
        .testTarget(
            name: "EmbroideryEngineTests",
            dependencies: ["EmbroideryEngine"],
            // .copy keeps the DST fixtures byte-identical (golden tests diff them byte by byte).
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "ProgramModelTests", dependencies: ["ProgramModel"]),
        .testTarget(name: "InterpreterTests", dependencies: ["Interpreter", "ProgramModel", "EmbroideryEngine"])
    ],
    swiftLanguageModes: [.v6]
)
