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

    // MARK: - swift-code-reviewer, slice 4: loops that exit at entry inside another loop

    /// Catroid's frame for each loop that exits at entry is a tick here too, so an outer loop
    /// whose body ends in one finishes on time. With the exit taking no tick, US-323 made the
    /// outer `loopEnd` find an action-free tick and yield — one tick late per nesting level.
    @Test("a loop exiting at entry as the last brick of a body keeps the outer loop on time", arguments: [
        ([.repeatLoop(times: .number(1)), tag(2), .repeatLoop(times: .number(0)), .loopEnd, .loopEnd], [[2], []]),
        ([.repeatLoop(times: .number(2)), .repeatLoop(times: .number(1)), tag(2),
          .repeatLoop(times: .number(0)), tag(1), .loopEnd, .loopEnd, .loopEnd, tag(9)], [[2], [], [2], [], [9]]),
        ([.repeatLoop(times: .number(1)), tag(2), .repeatUntil(condition: .constant(.true)), tag(1), .loopEnd,
          .loopEnd], [[2], []])
    ] as [([Brick], [[Double]])])
    func exitAtEntryKeepsOuterLoopOnTime(_ bricks: [Brick], _ expected: [[Double]]) {
        #expect(tagProfile(scripts: [bricks]) == expected)
    }

    /// Without the tick, the drift had no bound inside a `forever`.
    @Test("a forever whose body ends in a loop exiting at entry repeats every two ticks")
    func foreverDoesNotDrift() {
        var interpreter = Interpreter(
            program: Program(scenes: [Scene(objects: [Object(scripts: [Script(bricks: [
                .forever, .repeatLoop(times: .number(1)), Self.tag(2),
                .repeatUntil(condition: .constant(.true)), Self.tag(1), .loopEnd, .loopEnd, .loopEnd
            ])])])]),
            clock: InterpreterClock(tickDelta: 0.05)
        )
        let ticks = (0 ..< 6).map { _ -> [Double] in
            guard case let .ticked(batch) = interpreter.step() else { return [-1] }
            return batch.compactMap { if case let .needleMoved(_, update) = $0 { update.position.y } else { nil } }
        }
        #expect(ticks == [[2], [], [2], [], [2], []])
    }
}
