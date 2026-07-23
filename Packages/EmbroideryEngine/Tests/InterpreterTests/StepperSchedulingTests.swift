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

    // MARK: Item 4 — brick-by-brick interleaving (the Catroid-parity case)

    @Test("two scripts on one object interleave brick-by-brick, ending at (0, 20)")
    func sameObjectScriptsInterleaveBrickByBrick() {
        // Both scripts steer the SAME object's needle. Round-robin one brick per
        // thread per tick means B's move lands before A's turn:
        //   tick 1: A move → (0,10), B move → (0,20)
        //   tick 2: A turn → heading 90 (position unchanged)
        // A drain-A-first scheduler would turn before B moved and end at (10,10).
        let scriptA = Script(bricks: [.moveNSteps(.number(10)), .turnRight(.number(90))])
        let scriptB = Script(bricks: [.moveNSteps(.number(10))])
        let program = Program(scenes: [Scene(objects: [Object(scripts: [scriptA, scriptB])])])
        var interpreter = Interpreter(program: program, clock: clock)
        let actor = ActorID(0)

        let events = interpreter.run(maxTicks: 100)
        #expect(events == [
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 10))),
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 20))),
            .needleMoved(actor: actor, update: NeedleUpdate(position: StagePoint(x: 0, y: 20), heading: 90))
        ])
        // The discriminating end state: (0, 20), never (10, 10).
        if case let .needleMoved(_, update) = events.last {
            #expect(update.position == StagePoint(x: 0, y: 20))
        } else {
            Issue.record("expected a final needleMoved event")
        }
    }

    @Test("two objects each advance one brick per tick, in creation order")
    func twoObjectsAdvanceInCreationOrder() {
        let move = Script(bricks: [.moveNSteps(.number(10))])
        let program = Program(scenes: [Scene(objects: [
            Object(name: "first", scripts: [move]),
            Object(name: "second", scripts: [move])
        ])])
        var interpreter = Interpreter(program: program, clock: clock)

        // One tick: object 0's thread, then object 1's thread — creation order.
        #expect(interpreter.step() == .ticked([
            .needleMoved(actor: ActorID(0), update: NeedleUpdate(position: StagePoint(x: 0, y: 10))),
            .needleMoved(actor: ActorID(1), update: NeedleUpdate(position: StagePoint(x: 0, y: 10)))
        ]))
        #expect(interpreter.step() == .finished)
    }
}
