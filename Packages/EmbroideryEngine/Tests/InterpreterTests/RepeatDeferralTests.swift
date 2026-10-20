import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// Variables slice 4: US-323 (ADR-018 amendment, brief D11). A loop head reached after an action
/// in the same tick waits for the next tick **before** it reads its formula, as Catroid's
/// `RepeatAction` reads its count lazily on its own first act (`RepeatAction.kt:39-42`). Until
/// now the count was read a tick early, and another script's write in that tick was missed.
@Suite("Loop heads read their formula on their own first act")
struct RepeatDeferralTests {
    static func tag(_ y: Double) -> Brick {
        .setY(.number(y))
    }

    /// The backlog entry's probe: B moves the needle to x = 2 in tick 1, after A's `setY(1)`.
    /// Catroid's repeat reads `objectX` in tick 2, sees 2 and runs twice: (2, 3). Read a tick
    /// early it saw 0 and ran nothing: (2, 1).
    @Test("the US-323 probe ends at (2, 3)")
    func probe() {
        let program = Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: [Self.tag(1), .repeatLoop(times: .sensor(.objectX)), .changeYBy(.number(1)), .loopEnd]),
            Script(bricks: [.setX(.number(2))])
        ])])])
        var interpreter = Interpreter(program: program, clock: InterpreterClock(tickDelta: 0.05))
        let last = interpreter.run(maxTicks: 50).last { event in
            if case .needleMoved = event { true } else { false }
        }
        guard case let .needleMoved(_, update) = last else {
            Issue.record("no needle update")
            return
        }
        #expect(update.position == StagePoint(x: 2, y: 3))
    }

    @Test("a repeat after an action reads a variable another script wrote in that tick")
    func variableCount() {
        let profile = tagProfile(scripts: [
            [Self.tag(1), .repeatLoop(times: .variable("n")), Self.tag(5), .loopEnd],
            [.setVariable(name: "n", to: .number(2))]
        ])
        #expect(profile == [[1], [5], [5]])
    }

    /// The other half of the fix: a zero-count repeat reached after an action now takes the
    /// next tick to read its count, so a script ending in one finishes a tick later — as
    /// Catroid's, whose repeat acts in its own frame.
    @Test("a script ending in a zero-count repeat after an action finishes in the next tick")
    func zeroCountAtTheEnd() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [
                Script(bricks: [Self.tag(1), .repeatLoop(times: .number(0)), Self.tag(2), .loopEnd])
            ])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        #expect(stepToCompletion(&interpreter).count == 2)
    }
}
