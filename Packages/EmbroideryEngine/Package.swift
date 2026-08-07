// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EmbroideryEngine",
    // Required because Samples ships localized resources (US-301). Package-level,
    // so it costs the other targets nothing.
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "EmbroideryEngine", targets: ["EmbroideryEngine"]),
        .library(name: "ProgramModel", targets: ["ProgramModel"]),
        .library(name: "Interpreter", targets: ["Interpreter"]),
        .library(name: "Samples", targets: ["Samples"])
    ],
    targets: [
        .target(name: "EmbroideryEngine"),
        // ADR-016: the dependency arrow points inward only — ProgramModel depends on
        // nothing, Interpreter is the only place model and engine meet.
        .target(name: "ProgramModel"),
        .target(name: "Interpreter", dependencies: ["ProgramModel", "EmbroideryEngine"]),
        // ADR-022 app-support target: bundled sample programs, depending on
        // ProgramModel *only* — no EmbroideryEngine, no Interpreter — so the
        // ADR-016 DAG stays a straight line inward. US-302 adds StagePreview,
        // the fifth product.
        .target(
            name: "Samples",
            dependencies: ["ProgramModel"],
            // .process, deliberately unlike this manifest's two .copy declarations
            // below. Those diff DST bytes, so byte identity is the whole point;
            // here the guard is `decode(resource) == builder()`, a *value*
            // comparison that survives any re-encoding. .process also gives the
            // en.lproj/ localization layout its standard handling.
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "EmbroideryEngineTests",
            dependencies: ["EmbroideryEngine"],
            // .copy keeps the DST fixtures byte-identical (golden tests diff them byte by byte).
            resources: [.copy("Resources")]
        ),
        .testTarget(name: "ProgramModelTests", dependencies: ["ProgramModel"]),
        .testTarget(
            name: "InterpreterTests",
            dependencies: ["Interpreter", "ProgramModel", "EmbroideryEngine"],
            // .copy for the same reason as above: US-209 diffs the golden program's
            // DST bytes against this fixture byte by byte. SPM resources are declared
            // per target, so the interpreter-level golden cannot reach the engine test
            // target's fixtures and gets its own Resources directory.
            resources: [.copy("Resources")]
        ),
        // Samples itself may not see Interpreter/EmbroideryEngine (ADR-022); this
        // test target may, because the interpreter run and DST assertions live
        // here. SwiftPM forbids test→test dependencies, which is exactly why the
        // sample builders had to leave InterpreterTests in the first place.
        .testTarget(
            name: "SamplesTests",
            dependencies: ["Samples", "ProgramModel", "Interpreter", "EmbroideryEngine"]
        )
    ],
    swiftLanguageModes: [.v6]
)
