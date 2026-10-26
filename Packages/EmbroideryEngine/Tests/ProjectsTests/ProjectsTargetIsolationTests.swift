import Foundation
import Testing

/// US-329: `Projects` imports nothing above Foundation and Observation, so its suites and
/// mutants run under `swift test`; and it depends on `EditorCore`, `ProgramModel` and
/// `EmbroideryEngine` only. The same three-layer arrangement as `EditorCoreTargetIsolationTests`
/// (read its suite comment for each layer's limits): this source scan and a textual manifest
/// pin are the fast local signal, and CI's `dump-package` step pins the *evaluated* manifest.
///
/// The normaliser is a copy of `EditorCoreTargetIsolationTests.strippedAndNormalised`, hardened
/// there over three Codex rounds; SwiftPM forbids one test target depending on another, so it is
/// copied rather than shared. A fix to one belongs in both.
@Suite("Projects target isolation")
struct ProjectsTargetIsolationTests {
    private static let forbiddenModules = ["SwiftUI", "UIKit", "AppKit", "CoreGraphics"]

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

    private static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/ProjectsTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // <root>
    }

    @Test("Projects' sources import nothing above Foundation and Observation")
    func sourcesImportNothingAboveFoundation() throws {
        let sourceDirectory = Self.packageRoot.appendingPathComponent("Sources").appendingPathComponent("Projects")
        // Non-vacuity first: a scan over zero files would pass (ADR-032 invariant 2).
        let contents = try #require(
            try? FileManager.default.subpathsOfDirectory(atPath: sourceDirectory.path),
            "Projects' source directory must be reachable from #filePath"
        )
        let swiftFiles = contents.filter { $0.hasSuffix(".swift") }
        try #require(!swiftFiles.isEmpty)
        #expect(swiftFiles.contains { ($0 as NSString).lastPathComponent == "ProjectLibrary.swift" })

        for relativePath in swiftFiles {
            let file = sourceDirectory.appendingPathComponent(relativePath)
            let source = try Self.strippedAndNormalised(String(contentsOf: file, encoding: .utf8))
            for module in Self.forbiddenModules {
                let name = "`?\(module)`?"
                let kind = "(?:`?[A-Za-z_][A-Za-z0-9_]*`?\\s+)?"
                let pattern = "(?<![A-Za-z0-9_])import\\s+\(kind)\(name)(?![A-Za-z0-9_])"
                #expect(
                    source.range(of: pattern, options: .regularExpression) == nil,
                    "\(relativePath) imports \(module); Projects is Foundation-and-Observation (US-329)"
                )
            }
        }
    }

    /// The declaration's text, normalised; CI's `dump-package` step is the evaluated pin.
    @Test("Projects depends on EditorCore, ProgramModel and EmbroideryEngine only")
    func dependsOnItsThreeTargetsOnly() throws {
        let manifest = try Self.strippedAndNormalised(
            String(contentsOf: Self.packageRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
        )
        #expect(manifest.contains(
            #".target(name: "Projects", dependencies: ["EditorCore", "ProgramModel", "EmbroideryEngine"])"#
        ))
    }
}
