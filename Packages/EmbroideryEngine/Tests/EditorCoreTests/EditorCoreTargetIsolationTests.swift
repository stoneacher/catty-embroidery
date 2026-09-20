import EditorCore
import Foundation
import ProgramModel
import Testing

/// ADR-033: `EditorCore` depends on `ProgramModel` **only** among package
/// targets, and imports nothing above Foundation.
///
/// This suite deliberately does **not** copy
/// `StagePreviewTargetIsolationTests`' mechanism wholesale, and US-401's
/// acceptance criterion asks for the reason to be stated rather than assumed.
/// That suite binds public APIs to explicit function types and its own comment
/// says this is not dependency enforcement — it cannot see a source import at
/// all. `import CoreGraphics` compiles in any target with no manifest edge,
/// because it is an SDK module, so the function-type trick would miss exactly
/// the thing this criterion is about.
///
/// So three mechanisms sit here, each with a different and individually
/// insufficient guarantee:
///
/// 1. **A source scan** (`sourcesImportNothingAboveFoundation`) — the primary.
///    Guarantee: a SwiftUI/CoreGraphics/UIKit/AppKit import in this target's
///    *current source tree on disk* is red. It is textual, so a mention inside
///    a comment or string literal is a false positive; that is accepted
///    deliberately, because the failure is loud and obvious, and because a
///    tokenizer here would repeat ADR-023's regex-classifier mistake for a
///    benefit nobody needs. It says nothing about *transitive* imports — if
///    `ProgramModel` imported SwiftUI this scan is blind, which is that
///    target's problem and the DAG's.
/// 2. **A manifest pin** (`dependsOnProgramModelOnly`) — closes a hole the
///    criterion's own prose leaves open. The build stops an *unauthorised*
///    import, but nothing stops someone adding `"EmbroideryEngine"` to this
///    target's `dependencies` and then importing it legitimately. Mutation M12
///    demonstrates precisely that: the build stays green and only this test
///    goes red.
/// 3. **Function-type bindings** (`theEditorVocabularyBoundaryIsPackageTypes`)
///    — the repo's established pattern, and honestly thin *today*: this
///    story's API is `Brick`, `[Brick]`, `Script`, `[Int]` and two index
///    structs, none of which is about to sprout a `CGPoint`. It is kept
///    because it is the file US-402's `apply` and US-409's palette extend,
///    where the pressure is real — and because it is what makes this file's
///    red phase a genuine "no such module `EditorCore`".
///
/// **Foundation is not asserted against, and that is deliberate.** ADR-033
/// restricts package dependencies, not the standard library, and US-404 puts
/// `Data`/`JSONEncoder` in this target. A later reader completing the module
/// list with Foundation would make that story unbuildable.
@Suite("EditorCore target isolation")
struct EditorCoreTargetIsolationTests {
    /// Modules that must not appear in an `import` in this target. Foundation is
    /// absent on purpose — see the suite comment.
    private static let forbiddenModules = ["SwiftUI", "CoreGraphics", "UIKit", "AppKit"]

    /// The package root, derived from this file's compile-time path rather than
    /// hardcoded: `<root>/Tests/EditorCoreTests/<this file>`. Not a fixed path in
    /// the sense CLAUDE.md forbids — nothing is written, and the value is derived,
    /// so parallel execution is safe and the suite is read-only.
    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/EditorCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // <root>
    }

    @Test("EditorCore's sources import nothing above Foundation")
    func sourcesImportNothingAboveFoundation() throws {
        let sourceDirectory = Self.packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("EditorCore")

        // Non-vacuity first, and it is not ceremony: a scan over zero files
        // scores a flawless PASS, which is the exact shape of US-309's `drawn=0`
        // capture and the canonical failure ADR-032 invariant 2 names. Mutation
        // M11 points the scan at a directory that does not exist and must see
        // *this* require fail rather than the suite pass.
        let contents = try #require(
            try? FileManager.default.subpathsOfDirectory(atPath: sourceDirectory.path),
            "EditorCore's source directory must be reachable from #filePath"
        )
        let swiftFiles = contents.filter { $0.hasSuffix(".swift") }
        try #require(!swiftFiles.isEmpty)
        #expect(swiftFiles.contains { ($0 as NSString).lastPathComponent == "BrickKind.swift" })

        for relativePath in swiftFiles {
            let file = sourceDirectory.appendingPathComponent(relativePath)
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
                for module in Self.forbiddenModules {
                    // Matches `import X`, `@_exported import X`, the member form
                    // `import struct X.Y`, and the submodule form `import X.Y`.
                    let pattern = "(?:^|\\s)import\\s+(?:[A-Za-z]+\\s+)?\(module)\\b"
                    #expect(
                        line.range(of: pattern, options: .regularExpression) == nil,
                        "\(relativePath) imports \(module); EditorCore is Foundation-and-below (ADR-033)"
                    )
                }
            }
        }
    }

    @Test("the manifest gives EditorCore exactly one package dependency")
    func dependsOnProgramModelOnly() throws {
        let manifest = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // Whitespace-normalised so SwiftFormat cannot re-wrap the declaration into
        // a silent pass; re-wrapping it across lines is a deliberate red, and the
        // fix is to update this pin rather than to delete it. A `contains` pin,
        // not a parser — one claim, no regex surface.
        let normalised = manifest.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        #expect(normalised.contains(#".target(name: "EditorCore", dependencies: ["ProgramModel"])"#))
    }

    @Test("the editor vocabulary's boundary is ProgramModel and stdlib types")
    func theEditorVocabularyBoundaryIsPackageTypes() {
        let kind: (Brick) -> BrickKind = BrickKind.init(of:)
        let template: (BrickKind) -> [Brick] = { $0.template() }
        let depths: (Script) -> [Int] = { $0.indentDepths }
        let address: (Int) -> BrickAddress = { BrickAddress(brickIndex: $0) }

        let script = Script(bricks: [.forever, .stitch, .loopEnd])

        #expect(kind(.stitch) == BrickKind(of: .stitch))
        #expect(template(.sewUp) == BrickKind.sewUp.template())
        #expect(depths(script) == script.indentDepths)
        #expect(address(2) == BrickAddress(brickIndex: 2))
    }
}
