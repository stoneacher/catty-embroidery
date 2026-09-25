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
///
///    **What it pins is the declaration's text, not the evaluated graph**, and
///    Codex round 2 showed the difference is reachable: appending
///    `package.targets.first { $0.name == "EditorCore" }!.dependencies
///    .append("EmbroideryEngine")` after the initializer is legal, violates
///    ADR-033, and leaves every textual check green. The real oracle is
///    `swift package dump-package`, which *evaluates* the manifest — but
///    spawning it from inside `swift test` deadlocks on SwiftPM's build lock
///    (measured: it blocked for 608 s before being killed, it did not merely
///    run slowly). So the evaluated check runs in CI, one step before the test
///    suite, and this pin stays as the fast local signal. That split is
///    ADR-023's standing division exactly: the local check is a convenience
///    that catches mistakes, the required status check is the enforcement
///    boundary.
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

    /// Swift source with comments removed and every whitespace run — including
    /// newlines — collapsed to a single space.
    ///
    /// Both of these are load-bearing, and Codex round 1 found why by defeating
    /// the first version of this suite twice. An import may be split across
    /// lines (`import\nCoreGraphics`) or interrupted by a comment
    /// (`import /* why */ CoreGraphics`); the parser accepts both, and a
    /// line-by-line regex sees neither. And a *commented-out* declaration in
    /// `Package.swift` satisfied the manifest pin while the live declaration
    /// next to it violated ADR-033.
    ///
    /// Block comments collapse to a space, which is what lets the interrupted
    /// form close up into `import CoreGraphics` and match.
    ///
    /// The residual weakness is stated rather than hidden: this is not a Swift
    /// lexer, so a `//` or `/*` inside a string literal is treated as a comment.
    /// **That cuts both ways, and an earlier version of this comment claiming it
    /// "can only hide text" was wrong** (Codex round 3, ADR-032 invariant 3):
    /// since the fix, `let note = "import/* example */CoreGraphics"` normalises
    /// to `import CoreGraphics` and reds the suite, so misclassification can
    /// manufacture a match as well as suppress one. A false positive here is
    /// loud and one edit from resolved, which is why the policy stands.
    ///
    /// **The honest scope**: this catches every spelling an ordinary source file
    /// can express, and is not a proof. A NUL byte between `import` and the
    /// module name compiles with a warning and is not matched by `\s`. If this
    /// guarantee ever needs to be total rather than good, the answer is not a
    /// longer regex — it is a **Linux engine-test job**, where SwiftUI, UIKit,
    /// CoreGraphics and AppKit do not exist and any import of them is a hard
    /// build error. See ADR-023 on what happens to a text classifier that is
    /// asked to be exhaustive.
    private static func strippedAndNormalised(_ source: String) -> String {
        var stripped = ""
        var index = source.startIndex
        var blockDepth = 0

        while index < source.endIndex {
            let rest = source[index...]
            if rest.hasPrefix("/*") {
                blockDepth += 1
                index = source.index(index, offsetBy: 2)
            } else if blockDepth > 0 {
                if rest.hasPrefix("*/") {
                    blockDepth -= 1
                    index = source.index(index, offsetBy: 2)
                    // A comment is a token *separator* in Swift, so it collapses
                    // to a space rather than to nothing: `import/* why */Foo` is
                    // legal, and deleting the comment outright would splice it
                    // into `importFoo` and hide it (Codex round 2).
                    if blockDepth == 0 {
                        stripped.append(" ")
                    }
                } else {
                    index = source.index(after: index)
                }
            } else if rest.hasPrefix("//") {
                // `.isNewline`, not `!= "\n"`: Swift folds CRLF into a *single*
                // `Character` that does not equal `"\n"`, so the explicit
                // comparison ran past every line ending in a CRLF file and ate
                // the rest of the source — hiding a real `import CoreGraphics`
                // on the next line (Codex round 3, reproduced before fixing).
                while index < source.endIndex, !source[index].isNewline {
                    index = source.index(after: index)
                }
                stripped.append(" ")
            } else {
                stripped.append(source[index])
                index = source.index(after: index)
            }
        }
        return stripped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

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
            // Scanned as one normalised string rather than line by line, so an
            // import split across lines or interrupted by a comment cannot slip
            // between two individually-innocent lines.
            let source = try Self.strippedAndNormalised(String(contentsOf: file, encoding: .utf8))
            for module in Self.forbiddenModules {
                // Matches `import X`, `@_exported import X`, the member form
                // `import struct X.Y`, the submodule form `import X.Y`, the
                // backtick-escaped spelling, and an `import` separated by `;`
                // rather than whitespace — the last three found legal and
                // unmatched in Codex round 2.
                let name = "`?\(module)`?"
                let kind = "(?:`?[A-Za-z_][A-Za-z0-9_]*`?\\s+)?"
                let pattern = "(?<![A-Za-z0-9_])import\\s+\(kind)\(name)(?![A-Za-z0-9_])"
                #expect(
                    source.range(of: pattern, options: .regularExpression) == nil,
                    "\(relativePath) imports \(module); EditorCore is Foundation-and-below (ADR-033)"
                )
            }
        }
    }

    /// US-403's acceptance criterion is stricter than the target's: the undo
    /// stack is "pure, `Sendable`, **no Foundation**", while the target as a
    /// whole may import Foundation (US-404 needs it — see the suite comment). So
    /// the stricter rule is pinned per file, not added to `forbiddenModules`.
    @Test("the undo stack's sources do not import Foundation")
    func undoSourcesImportNoFoundation() throws {
        let sourceDirectory = Self.packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent("EditorCore")
        let pattern = "(?<![A-Za-z0-9_])import\\s+(?:`?[A-Za-z_][A-Za-z0-9_]*`?\\s+)?`?Foundation`?(?![A-Za-z0-9_])"

        for name in ["UndoStack.swift", "CoalescingKey.swift"] {
            // `#require` on the read, so a renamed or missing file is red rather
            // than a scan over nothing.
            let source = try #require(
                try? String(contentsOf: sourceDirectory.appendingPathComponent(name), encoding: .utf8),
                "\(name) must exist in Sources/EditorCore"
            )
            #expect(
                Self.strippedAndNormalised(source).range(of: pattern, options: .regularExpression) == nil,
                "\(name) imports Foundation; US-403's undo stack is Foundation-free"
            )
        }
    }

    @Test("the manifest's EditorCore declaration is the pinned, unique one")
    func dependsOnProgramModelOnly() throws {
        let manifest = try String(
            contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        // Comments are stripped before the pin, because a commented-out copy of
        // the correct declaration satisfied the first version while the live one
        // beside it added a second dependency (Codex round 1). Whitespace is
        // normalised so SwiftFormat cannot re-wrap the declaration into a silent
        // pass; re-wrapping it is a deliberate red, and the fix is to update this
        // pin rather than delete it.
        let normalised = Self.strippedAndNormalised(manifest)
        #expect(normalised.contains(#".target(name: "EditorCore", dependencies: ["ProgramModel"])"#))
        // …and it is the *only* declaration of the target, so the pinned one
        // cannot sit beside a second, live one that widens the dependencies.
        #expect(normalised.components(separatedBy: #".target(name: "EditorCore""#).count - 1 == 1)
    }

    @Test("the editor vocabulary's boundary is ProgramModel and stdlib types")
    func theEditorVocabularyBoundaryIsPackageTypes() {
        let kind: (Brick) -> BrickKind = BrickKind.init(of:)
        let template: (BrickKind) -> [Brick] = { $0.template() }
        let depths: (Script) -> [Int] = { $0.indentDepths }
        let address: (Int) -> BrickAddress = { BrickAddress(brickIndex: $0) }

        // Asserted against independently known values, not against the same call
        // made directly: `depths(script) == script.indentDepths` is true of *any*
        // implementation, including one returning all zeros, so it discriminates
        // nothing (Codex round 1). The compile-time signature claim above is what
        // this test is for, but its runtime half should not be a tautology.
        #expect(kind(.stitch) == .stitch)
        #expect(template(.sewUp) == [.sewUp])
        #expect(depths(Script(bricks: [.forever, .stitch, .loopEnd])) == [0, 1, 0])
        #expect(address(2).brickIndex == 2)
    }

    /// US-403: the undo API speaks `Program`, `EditAction`, `EditResult` and
    /// `BrickAddress` only.
    @Test("the undo stack's boundary is editor and ProgramModel types")
    func theUndoBoundaryIsPackageTypes() {
        let make: (Program) -> UndoStack = UndoStack.init(program:)
        let apply: (inout UndoStack, EditAction, CoalescingKey?) -> EditResult = {
            $0.apply($1, coalescing: $2)
        }
        let undo: (inout UndoStack) -> Program? = { $0.undo() }
        let begin: (inout UndoStack, BrickAddress) -> CoalescingKey = { $0.beginEdit(of: $1) }

        let seed = Program(name: "seed", scenes: [])
        var renamed = seed
        renamed.name = "renamed"

        var stack = make(seed)
        let key = begin(&stack, BrickAddress(brickIndex: 0))
        #expect(key.address == BrickAddress(brickIndex: 0))
        #expect(apply(&stack, .renameProgram("renamed"), nil) == .applied(renamed))
        #expect(undo(&stack) == seed)
    }
}
