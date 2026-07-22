import EmbroideryEngine
import Interpreter
import ProgramModel
import Testing

/// US-205 test-plan items 1, 2 (and later 4, 7): the round-robin scheduler and
/// the batch/step-by-step equivalence. One tick advances each runnable thread by
/// exactly one brick-derived instruction (ADR-018).
@Suite("Stepper scheduling")
struct StepperSchedulingTests {
    private let clock = InterpreterClock(tickDelta: 0.05)

    // MARK: Item 1 — empty program

    @Test("an empty program finishes on the first step and runs to no events")
    func emptyProgramFinishesImmediately() {
        var stepped = Interpreter(program: Program(), clock: clock)
        #expect(stepped.step() == .finished)
        #expect(stepped.isFinished)

        var ran = Interpreter(program: Program(), clock: clock)
        #expect(ran.run(maxTicks: 100) == [])
    }

    // MARK: Item 2 — one script, three moves, one brick per tick, in order

    @Test("three moves emit three needleMoved events in brick order, one per tick")
    func threeMovesEmitOnePerTickInOrder() {
        let script = Script(bricks: [
            .moveNSteps(.number(10)),
            .moveNSteps(.number(10)),
            .moveNSteps(.number(10))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)

        // Heading 0° → each move advances +y by 10 (dx = 10·sin0 = 0, dy = 10·cos0 = 10).
        let actor = ActorID(0)
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 20)))
        ]))
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 30)))
        ]))

        // The script is exhausted after its third brick.
        #expect(interpreter.step() == .finished)
        #expect(interpreter.isFinished)
    }

    @Test("run batches the same three needleMoved events a step-by-step consumer sees")
    func runMatchesThreeMoves() {
        let script = Script(bricks: [
            .moveNSteps(.number(10)),
            .moveNSteps(.number(10)),
            .moveNSteps(.number(10))
        ])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [script])])])
        var interpreter = Interpreter(program: program, clock: clock)
        let actor = ActorID(0)

        #expect(interpreter.run(maxTicks: 100) == [
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10))),
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 20))),
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 30)))
        ])
    }
}
