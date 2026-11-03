import CatrobatImport
import Foundation
import ProgramModel
import Testing

/// Slice 4 over the real corpus: every one of the 215 programs imports or names
/// why not, and every import is a valid program.
struct CorpusProgramTests {
    static func outcome(of entry: LanguageTestManifest.Entry) throws -> Result<ImportedProgram, CatrobatImportError> {
        let data = try LanguageTestCatalog.codeXML(for: entry.path)
        do {
            return try .success(CatrobatImport.program(fromCodeXML: data))
        } catch {
            return .failure(error)
        }
    }

    /// The 36 tests that import: the planning census's 34 runnable, minus the two
    /// that store strings (`testForLoopWithChangeVariableBrick`, `testSetAddVar`),
    /// plus the four the small additions bring in (brief, feasibility table).
    static let importable: [String] = [
        "brick/testDisabledBrickInLoopRegression",
        "brick/testRepeatBrick",
        "bricks/control/testForVariableFromToBrick",
        "bricks/control/testIfElse",
        "bricks/control/testRepeat",
        "bricks/control/testRepeatUntil",
        "bricks/control/testRepeatUntilBrick",
        "bricks/control/testWaitUntilAllOtherScriptsHaveStopped",
        "bricks/events/testEmptyEvent",
        "bricks/motion/testChangeXby",
        "formula/testAbsolutValueFunction",
        "formula/testArccosineFunction",
        "formula/testArcsinusFunction",
        "formula/testArctangent2FunctionNormalParameters",
        "formula/testArctangent2FunctionZeroParameters",
        "formula/testCeilingFunction",
        "formula/testCosinusFunction",
        "formula/testDecimalLogarithmFunction",
        "formula/testExponentFunction",
        "formula/testFloatingPointArithmetic",
        "formula/testFloorFunction",
        "formula/testMaximumOfFunction",
        "formula/testMinimumOfFunction",
        "formula/testModuloFunction",
        "formula/testNaturalLogarithmFunction",
        "formula/testPowerFunction",
        "formula/testRoundFunction",
        "formula/testSineFunction",
        "formula/testSquareRootFunction",
        "formula/testTangentFunction",
        "motion/testChangeXPosition",
        "motion/testChangeYPosition",
        "motion/testMoveXStepsFunction",
        "motion/testPointInDirectionDegrees",
        "motion/testSetYPosition",
        "motion/testTurnXDegrees"
    ]

    @Test func exactlyThePinnedTestsImport() throws {
        var imported: [String] = []
        for entry in try LanguageTestCatalog.manifest().tests {
            if case .success = try Self.outcome(of: entry) { imported.append(entry.path) }
        }
        #expect(imported == Self.importable)
    }

    /// How many refused tests each blocker kind appears in. Every refusal names
    /// something ADR-001 leaves out, a kept string, or the D4 storage rule.
    @Test func blockerKindsAcrossTheCorpus() throws {
        var kinds: [String: Int] = [:]
        for entry in try LanguageTestCatalog.manifest().tests {
            guard case let .failure(error) = try Self.outcome(of: entry) else { continue }
            for kind in Set(error.blockers.map { CorpusFormulaTests.kind(of: $0).prefix { $0 != "(" } }) {
                kinds[String(kind), default: 0] += 1
            }
        }
        #expect(kinds == [
            "brick": 153,
            "brickShape": 2,
            "elementType": 26,
            "function": 54,
            "multipleScenes": 10,
            "script": 80,
            "sensor": 32,
            "stringValue": 43,
            "variableStorage": 1
        ])
    }

    /// Every imported script's bricks form a valid ADR-008 script, harness steps
    /// aside (they are leaves); slice 5 relies on it.
    @Test(arguments: importable)
    func everyImportIsAValidProgram(path: String) throws {
        let entry = try #require(LanguageTestCatalog.entries.first { $0.path == path })
        let program = try Self.outcome(of: entry).get()
        for object in program.objects {
            for script in object.scripts {
                let bricks = script.steps.compactMap { step -> Brick? in
                    if case let .brick(brick) = step { brick } else { nil }
                }
                #expect(throws: Never.self, "\(path) \(object.name)") {
                    try Script(header: .whenStarted, bricks: bricks).validate()
                }
            }
        }
    }

    /// The storage rule's corpus case: this test checks that a loop ends when its
    /// control variable stops being a number, the very divergence D4 refuses.
    @Test func theStorageRuleCatchesTheTestThatChecksIt() throws {
        let entry = try #require(LanguageTestCatalog.entries.first {
            $0.path == "bricks/control/testForLoopWithChangeVariableBrick"
        })
        guard case let .failure(error) = try Self.outcome(of: entry) else {
            Issue.record("expected a refusal")
            return
        }
        #expect(error.blockers.contains(.variableStorage("controlVariable")))
    }
}
