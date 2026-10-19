import Interpreter
import ProgramModel
import Testing

/// Variables slice 2: the If bricks exist before their execution does (slice 3), so a script
/// holding one compiles to nothing rather than to its bricks with the If ignored — which would
/// move unconditionally and run both branches of an If/Else (`swift-code-reviewer`, slice 2:
/// the guard had no test). Slice 3 replaces this suite with the real semantics.
@Suite("If bricks before slice 3")
struct IfInertTests {
    @Test("a script with an If runs nothing", arguments: [
        [.ifThen(condition: .constant(.false)), .moveNSteps(.number(10)), .ifEnd],
        [.ifElse(condition: .constant(.true)), .moveNSteps(.number(10)), .elseBranch, .moveNSteps(.number(20)),
         .ifEnd],
        [.moveNSteps(.number(5)), .ifThen(condition: .constant(.true)), .ifEnd]
    ] as [[Brick]])
    func inert(_ bricks: [Brick]) {
        var interpreter = Interpreter(program: Program(scenes: [Scene(objects: [Object(scripts: [
            Script(bricks: bricks)
        ])])]), clock: InterpreterClock(tickDelta: 0.05))
        #expect(interpreter.run(maxTicks: 10).isEmpty)
    }
}
