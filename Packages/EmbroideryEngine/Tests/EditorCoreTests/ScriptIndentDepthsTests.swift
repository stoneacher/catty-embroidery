import EditorCore
import ProgramModel
import Testing

/// US-401 test-plan items 6–7: `Script.indentDepths`, the per-row nesting depth
/// US-407 renders as indentation.
///
/// The load-bearing case is the `loopEnd`, which sits at its **opener's** depth
/// rather than its body's. That is the mistake the story names as plausible,
/// and only `oneLoopReturnsItsEndToTheOpenerDepth` and `nestedLoopsAccumulate`
/// discriminate it — the flat, unbalanced and count tests all stay green under
/// it (mutation M1).
@Suite("Script indent depths")
struct ScriptIndentDepthsTests {
    struct DepthCase: Sendable {
        let name: String
        let script: Script
        let expected: [Int]
    }

    /// Scripts the model permits but no `EditAction` can create (ADR-035): a
    /// bare `loopEnd`, an opener that is never closed, and both at once. They
    /// must yield depths rather than trap, and must never go negative.
    static let unbalanced: [Script] = [
        Script(bricks: [.loopEnd]),
        Script(bricks: [.loopEnd, .stitch]),
        Script(bricks: [.forever]),
        Script(bricks: [.forever, .stitch]),
        Script(bricks: [.loopEnd, .forever, .stitch, .loopEnd, .loopEnd])
    ]

    static let balanced: [Script] = [
        Script(bricks: []),
        Script(bricks: [.stitch, .moveNSteps(.number(1)), .sewUp]),
        Script(bricks: [.forever, .stitch, .stitch, .loopEnd]),
        Script(bricks: [.forever, .repeatLoop(times: .number(2)), .stitch, .loopEnd, .loopEnd])
    ]

    /// Test plan 6, first clause.
    @Test("a flat script indents every brick at zero")
    func flatScriptIndentsAllZero() {
        let script = Script(bricks: [.stitch, .moveNSteps(.number(1)), .sewUp])
        #expect(script.indentDepths == [0, 0, 0])
    }

    /// Test plan 6, second clause — the `loopEnd` is back at the opener's depth,
    /// not the body's.
    @Test("one loop indents its body and returns its end to the opener's depth")
    func oneLoopReturnsItsEndToTheOpenerDepth() {
        #expect(Script(bricks: [.forever, .stitch, .stitch, .loopEnd]).indentDepths == [0, 1, 1, 0])
        #expect(
            Script(bricks: [.repeatLoop(times: .number(3)), .stitch, .loopEnd]).indentDepths
                == [0, 1, 0]
        )
    }

    /// Test plan 6, third clause.
    @Test("nested loops accumulate depth")
    func nestedLoopsAccumulate() {
        let script = Script(bricks: [
            .forever, .repeatLoop(times: .number(2)), .stitch, .loopEnd, .loopEnd
        ])
        #expect(script.indentDepths == [0, 1, 2, 1, 0])
    }

    /// Test plan 6, fourth clause. The `>= 0` assertion is not decoration: the
    /// leading-`loopEnd` cases are the only ones in the suite that discriminate
    /// the clamp (mutation M2).
    @Test("an unbalanced script yields depths without trapping or going negative",
          arguments: ScriptIndentDepthsTests.unbalanced)
    func unbalancedScriptsYieldNonNegativeDepths(_ script: Script) {
        let depths = script.indentDepths
        #expect(depths.allSatisfy { $0 >= 0 })
        #expect(depths.count == script.bricks.count)
    }

    /// Test plan 7 — including the empty script. This is a *narrower* claim than
    /// correctness and is not a proxy for it: replacing the whole function with
    /// `Array(repeating: 0, count: bricks.count)` keeps it green (mutation M4).
    @Test("indentDepths returns exactly one depth per brick",
          arguments: ScriptIndentDepthsTests.balanced + ScriptIndentDepthsTests.unbalanced)
    func indentDepthsReturnsOneDepthPerBrick(_ script: Script) {
        #expect(script.indentDepths.count == script.bricks.count)
    }
}
